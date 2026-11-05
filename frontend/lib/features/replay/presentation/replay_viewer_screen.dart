import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gully_umpire/app/theme/app_colors.dart';
import 'package:gully_umpire/app/theme/app_spacing.dart';
import 'package:gully_umpire/core/di/data_providers.dart';
import 'package:gully_umpire/core/widgets/empty_state.dart';
import 'package:gully_umpire/core/widgets/message_banner.dart';
import 'package:gully_umpire/core/widgets/status_chip.dart';
import 'package:gully_umpire/cv/live/replay_codec.dart';
import 'package:gully_umpire/cv/live/replay_meta.dart';
import 'package:gully_umpire/data/replays/replay_store.dart';
import 'package:gully_umpire/features/replay/presentation/replay_overlay_painter.dart';
import 'package:gully_umpire/features/replay/replay_geometry.dart';
import 'package:gully_umpire/features/replay/replay_image.dart';

/// Plays back the pictures the umpire camera recorded for one ball, with the ball path, the
/// batter's waist, shoulder and head lines and the measured height drawn on top.
///
/// The pictures are kept in a compact file on the phone (and, once uploaded, on the server), so a
/// replay opens without a network and shows exactly what the camera measured.
class ReplayViewerScreen extends ConsumerStatefulWidget {
  const ReplayViewerScreen({super.key, required this.replayId});

  /// Id of the replay file.
  final String replayId;

  @override
  ConsumerState<ReplayViewerScreen> createState() => _ReplayViewerScreenState();
}

class _ReplayViewerScreenState extends ConsumerState<ReplayViewerScreen> {
  static const Duration _tick = Duration(milliseconds: 30);
  static const List<double> _speeds = <double>[0.25, 0.5, 1];

  ReplayReader? _reader;
  ReplayMeta? _meta;
  String? _problem;
  bool _loading = true;

  ui.Image? _image;
  int _index = 0;
  bool _playing = false;
  double _speed = 0.5;
  double _clockMs = 0;
  bool _decoding = false;
  int? _wantedIndex;
  bool _showLines = true;
  Timer? _timer;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _image?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final ReplayStore? store = ref.read(replayStoreProvider);
    Uint8List? bytes;
    try {
      bytes = await store?.read(widget.replayId);
    } on Object {
      bytes = null;
    }
    if (_disposed) {
      return;
    }
    if (bytes == null) {
      setState(() {
        _loading = false;
        _problem = 'This replay is no longer on this phone.';
      });
      return;
    }
    final ReplayReader reader;
    try {
      reader = ReplayReader.parse(bytes);
    } on ReplayFormatException {
      setState(() {
        _loading = false;
        _problem = 'This replay file is damaged and cannot be played.';
      });
      return;
    }
    ReplayMeta? meta;
    final Map<String, Object?>? raw = reader.meta;
    if (raw != null) {
      try {
        meta = ReplayMeta.fromJson(raw);
      } on Object {
        meta = null;
      }
    }
    _reader = reader;
    _meta = meta;
    // Start on the picture where the ball reaches the batter: that is the one the call is about.
    final int? arrival = meta?.arrivalMs;
    _index = arrival == null ? 0 : reader.indexAt(arrival);
    _clockMs = (reader.timestampOf(_index) - reader.timestampOf(0)).toDouble();
    await _showFrame(_index);
    if (_disposed) {
      return;
    }
    setState(() => _loading = false);
  }

  // ---- Playback ----------------------------------------------------------------------------

  Future<void> _showFrame(int index) async {
    final ReplayReader? reader = _reader;
    if (reader == null) {
      return;
    }
    if (_decoding) {
      // Only the newest wish matters while a picture is being prepared.
      _wantedIndex = index;
      return;
    }
    _decoding = true;
    try {
      final Uint8List luma = reader.frame(index);
      final ui.Image image = await lumaToImage(luma, reader.width, reader.height);
      if (_disposed) {
        image.dispose();
        return;
      }
      final ui.Image? old = _image;
      setState(() {
        _image = image;
        _index = index;
      });
      old?.dispose();
    } on Object catch (_) {
      if (!_disposed) {
        setState(() => _problem = 'A picture of this replay could not be read.');
      }
    } finally {
      _decoding = false;
    }
    final int? wanted = _wantedIndex;
    _wantedIndex = null;
    if (!_disposed && wanted != null && wanted != _index) {
      await _showFrame(wanted);
    }
  }

  void _play() {
    final ReplayReader? reader = _reader;
    if (reader == null || reader.frameCount < 2) {
      return;
    }
    if (_index >= reader.frameCount - 1) {
      _clockMs = 0;
      unawaited(_showFrame(0));
    }
    setState(() => _playing = true);
    _timer?.cancel();
    _timer = Timer.periodic(_tick, (_) => _advance());
  }

  void _pause() {
    _timer?.cancel();
    _timer = null;
    if (_playing) {
      setState(() => _playing = false);
    }
  }

  void _advance() {
    final ReplayReader? reader = _reader;
    if (reader == null || _disposed) {
      return;
    }
    final double duration = reader.durationMs.toDouble();
    _clockMs += _tick.inMilliseconds * _speed;
    if (_clockMs >= duration) {
      _clockMs = duration;
      _pause();
    }
    final int index = reader.indexAt(reader.timestampOf(0) + _clockMs.round());
    if (index != _index) {
      unawaited(_showFrame(index));
    }
  }

  void _seek(int index) {
    final ReplayReader? reader = _reader;
    if (reader == null) {
      return;
    }
    final int target = index < 0 ? 0 : (index >= reader.frameCount ? reader.frameCount - 1 : index);
    _pause();
    _clockMs = (reader.timestampOf(target) - reader.timestampOf(0)).toDouble();
    unawaited(_showFrame(target));
  }

  void _seekToTime(int? timestampMs) {
    final ReplayReader? reader = _reader;
    if (reader == null || timestampMs == null) {
      return;
    }
    _seek(reader.indexAt(timestampMs));
  }

  // ---- Building ----------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Replay')),
      body: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final ReplayReader? reader = _reader;
    if (_problem != null && (reader == null || _image == null)) {
      return EmptyState(
        icon: Icons.videocam_off_outlined,
        title: 'No replay',
        message: _problem,
        actionLabel: 'Go back',
        onAction: () => Navigator.of(context).maybePop(),
      );
    }
    if (reader == null) {
      return const SizedBox.shrink();
    }
    final ReplayMeta? meta = _meta;
    final int timestampMs = reader.timestampOf(_index);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenPadding,
            AppSpacing.sm,
            AppSpacing.screenPadding,
            AppSpacing.xxl,
          ),
          children: <Widget>[
            _picture(reader, meta, timestampMs),
            const SizedBox(height: AppSpacing.sm),
            _scrubber(reader, timestampMs),
            _controls(context, reader, meta),
            const SizedBox(height: AppSpacing.md),
            if (meta == null)
              const MessageBanner(
                kind: BannerKind.info,
                message: 'The pictures play, but the measurements that go with this replay could '
                    'not be read.',
              )
            else
              _Measurements(meta: meta),
            if (_problem != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              MessageBanner(kind: BannerKind.warning, message: _problem!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _picture(ReplayReader reader, ReplayMeta? meta, int timestampMs) {
    final ui.Image? image = _image;
    final double aspect = reader.height == 0 ? 3 / 4 : reader.width / reader.height;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 460),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: aspect,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                const ColoredBox(color: Colors.black),
                if (image != null) RawImage(image: image, fit: BoxFit.fill),
                if (meta != null)
                  CustomPaint(
                    painter: ReplayOverlayPainter(
                      meta: meta,
                      timestampMs: timestampMs,
                      showBodyLines: _showLines,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _scrubber(ReplayReader reader, int timestampMs) {
    final TextTheme text = Theme.of(context).textTheme;
    final int last = reader.frameCount - 1;
    final double seconds = (timestampMs - reader.timestampOf(0)) / 1000;
    return Column(
      children: <Widget>[
        if (last > 0)
          Slider(
            min: 0,
            max: last.toDouble(),
            divisions: last,
            value: _index.clamp(0, last).toDouble(),
            onChanged: (double value) => _seek(value.round()),
          ),
        Text(
          'Picture ${_index + 1} of ${reader.frameCount} · ${seconds.toStringAsFixed(2)} s',
          style: text.bodySmall?.copyWith(color: AppColors.inkMuted),
        ),
      ],
    );
  }

  Widget _controls(BuildContext context, ReplayReader reader, ReplayMeta? meta) {
    return Column(
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            IconButton(
              tooltip: 'One picture back',
              icon: const Icon(Icons.skip_previous),
              onPressed: _index > 0 ? () => _seek(_index - 1) : null,
            ),
            IconButton.filled(
              tooltip: _playing ? 'Pause' : 'Play',
              iconSize: 32,
              icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
              onPressed: _playing ? _pause : _play,
            ),
            IconButton(
              tooltip: 'One picture forward',
              icon: const Icon(Icons.skip_next),
              onPressed: _index < reader.frameCount - 1 ? () => _seek(_index + 1) : null,
            ),
          ],
        ),
        Wrap(
          spacing: AppSpacing.sm,
          alignment: WrapAlignment.center,
          children: <Widget>[
            for (final double speed in _speeds)
              ChoiceChip(
                label: Text(speed == 1 ? 'Normal speed' : '${_speedLabel(speed)} speed'),
                selected: _speed == speed,
                onSelected: (_) => setState(() => _speed = speed),
              ),
          ],
        ),
        if (meta != null)
          Wrap(
            spacing: AppSpacing.sm,
            alignment: WrapAlignment.center,
            children: <Widget>[
              if (meta.bounced == true && meta.bounceMs != null)
                TextButton(
                  onPressed: () => _seekToTime(meta.bounceMs),
                  child: const Text('Go to the bounce'),
                ),
              if (meta.arrivalMs != null)
                TextButton(
                  onPressed: () => _seekToTime(meta.arrivalMs),
                  child: const Text('Go to the batter'),
                ),
              if (meta.contactMs != null)
                TextButton(
                  onPressed: () => _seekToTime(meta.contactMs),
                  child: const Text('Go to the path change'),
                ),
              TextButton(
                onPressed: () => setState(() => _showLines = !_showLines),
                child: Text(_showLines ? 'Hide the body lines' : 'Show the body lines'),
              ),
            ],
          ),
      ],
    );
  }

  static String _speedLabel(double speed) {
    if (speed == 0.25) {
      return 'Quarter';
    }
    if (speed == 0.5) {
      return 'Half';
    }
    return 'Normal';
  }
}

/// What the camera measured for the ball, in plain words.
class _Measurements extends StatelessWidget {
  const _Measurements({required this.meta});

  final ReplayMeta meta;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final String? height = ballHeightText(meta);
    final double? speed = meta.speedKmph;
    final double? margin = meta.heightUncertaintyM;
    final String marginText = margin == null ? 'about 0.3 m' : metresLabel(margin);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'What the camera measured',
              style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpacing.sm),
            _row(
              context,
              'Ball height at the batter',
              height ?? 'Could not be worked out',
            ),
            _row(context, 'Batter’s height used', metresLabel(meta.batterHeightM)),
            _row(context, 'Bounce', bounceText(meta)),
            if (pathChangeText(meta) case final String change)
              _row(context, 'Path near the batter', change),
            if (speed != null) _row(context, 'Speed', 'about ${speed.round()} km/h (rough)'),
            for (final ReplayVerdict verdict in meta.verdicts) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: <Widget>[
                  StatusChip(label: verdict.label),
                  StatusChip(
                    label: '${verdict.result.replaceAll('_', ' ').toLowerCase()} · '
                        '${(verdict.confidence * 100).round()}%',
                    foreground: AppColors.inkMuted,
                    background: AppColors.outline,
                  ),
                ],
              ),
              if (verdict.summary.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.xs),
                Text(verdict.summary, style: text.bodyMedium),
              ],
            ],
            for (final String note in meta.notes) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              Text(note, style: text.bodySmall?.copyWith(color: AppColors.inkMuted)),
            ],
            const SizedBox(height: AppSpacing.md),
            MessageBanner(
              kind: BannerKind.info,
              title: 'Judge it with your own eyes too',
              message: 'The height comes from one camera, so it can be off by $marginText. The '
                  'lines show where the batter’s waist and shoulder were worked out to be. The '
                  'dashed line only shows which way the ball was heading in the picture: one '
                  'camera cannot tell how far away things are, so a line that crosses the stumps '
                  'does not prove the ball would have hit them, and a change of path may be bat, '
                  'pad or glove. Step through the pictures yourself. The umpire makes the final '
                  'call.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            flex: 5,
            child: Text(label, style: text.bodyMedium?.copyWith(color: AppColors.inkMuted)),
          ),
          Expanded(
            flex: 6,
            child: Text(value, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
