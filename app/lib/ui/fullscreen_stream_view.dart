import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../core/utils/window_utils.dart';
import 'receiver_view.dart';

class FullscreenStreamView extends StatefulWidget {
  final ActiveStreamTile tile;
  final VoidCallback onMuteChanged;

  const FullscreenStreamView({
    super.key,
    required this.tile,
    required this.onMuteChanged,
  });

  @override
  State<FullscreenStreamView> createState() => _FullscreenStreamViewState();
}

class _FullscreenStreamViewState extends State<FullscreenStreamView> {
  RTCVideoViewObjectFit _fitMode = RTCVideoViewObjectFit.RTCVideoViewObjectFitContain;
  bool _showControls = true;
  Timer? _hideTimer;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WindowUtils.setFullScreen(true);
    _resetHideTimer();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _focusNode.dispose();
    WindowUtils.exitFullScreen();
    super.dispose();
  }

  void _resetHideTimer() {
    _hideTimer?.cancel();
    if (!_showControls) {
      setState(() => _showControls = true);
    }
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleFitMode() {
    setState(() {
      _fitMode = (_fitMode == RTCVideoViewObjectFit.RTCVideoViewObjectFitContain)
          ? RTCVideoViewObjectFit.RTCVideoViewObjectFitCover
          : RTCVideoViewObjectFit.RTCVideoViewObjectFitContain;
    });
    _resetHideTimer();
  }

  void _exitFullscreen() {
    WindowUtils.exitFullScreen();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final hasAudio = widget.tile.renderer.srcObject?.getAudioTracks().isNotEmpty ?? false;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.escape ||
              event.logicalKey == LogicalKeyboardKey.keyF ||
              event.logicalKey == LogicalKeyboardKey.f11) {
            _exitFullscreen();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.keyM) {
            widget.tile.toggleMute();
            widget.onMuteChanged();
            setState(() {});
            _resetHideTimer();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.space) {
            _toggleFitMode();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        cursor: _showControls ? SystemMouseCursors.basic : SystemMouseCursors.none,
        onHover: (_) => _resetHideTimer(),
        child: GestureDetector(
          onTap: () {
            if (!_showControls) {
              _resetHideTimer();
            } else {
              setState(() => _showControls = false);
            }
          },
          onDoubleTap: _toggleFitMode,
          child: Scaffold(
            backgroundColor: Colors.black,
            body: Stack(
              fit: StackFit.expand,
              children: [
                Center(
                  child: RTCVideoView(
                    widget.tile.renderer,
                    objectFit: _fitMode,
                  ),
                ),

                // Top Floating Control Bar
                AnimatedOpacity(
                  opacity: _showControls ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  child: IgnorePointer(
                    ignoring: !_showControls,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.8),
                              Colors.transparent,
                            ],
                          ),
                        ),
                        child: SafeArea(
                          child: Row(
                            children: [
                              IconButton.filledTonal(
                                onPressed: _exitFullscreen,
                                icon: const Icon(Icons.arrow_back, color: Colors.white),
                                tooltip: 'Tam Ekrandan Çık (Esc)',
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.black.withValues(alpha: 0.6),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.white24),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.cast_connected, color: Colors.cyanAccent, size: 16),
                                    const SizedBox(width: 8),
                                    Text(
                                      widget.tile.name,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: (hasAudio && !widget.tile.isMuted)
                                      ? Colors.green.withValues(alpha: 0.3)
                                      : Colors.orange.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: (hasAudio && !widget.tile.isMuted)
                                        ? Colors.greenAccent
                                        : Colors.orangeAccent,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      (hasAudio && !widget.tile.isMuted) ? Icons.volume_up : Icons.volume_off,
                                      color: (hasAudio && !widget.tile.isMuted)
                                          ? Colors.greenAccent
                                          : Colors.orangeAccent,
                                      size: 15,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      !hasAudio
                                          ? 'Ses Yok'
                                          : (widget.tile.isMuted ? 'Sessiz' : 'Ses %${(widget.tile.volume * 100).toInt()}'),
                                      style: TextStyle(
                                        color: (hasAudio && !widget.tile.isMuted)
                                            ? Colors.greenAccent
                                            : Colors.orangeAccent,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Spacer(),
                              // Volume Slider and Quick Boost
                              if (hasAudio) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.6),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.white24),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: Icon(
                                          widget.tile.isMuted ? Icons.volume_off : Icons.volume_up,
                                          color: widget.tile.isMuted ? Colors.redAccent : Colors.cyanAccent,
                                          size: 18,
                                        ),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        tooltip: widget.tile.isMuted ? 'Sesi Aç (M)' : 'Sesi Kapat (M)',
                                        onPressed: () async {
                                          await widget.tile.toggleMute();
                                          widget.onMuteChanged();
                                          if (mounted) setState(() {});
                                          _resetHideTimer();
                                        },
                                      ),
                                      const SizedBox(width: 6),
                                      SizedBox(
                                        width: 110,
                                        child: SliderTheme(
                                          data: SliderTheme.of(context).copyWith(
                                            trackHeight: 3,
                                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                                            activeTrackColor: widget.tile.volume > 1.0 ? Colors.orangeAccent : Colors.cyanAccent,
                                            inactiveTrackColor: Colors.white24,
                                            thumbColor: widget.tile.volume > 1.0 ? Colors.orangeAccent : Colors.cyanAccent,
                                          ),
                                          child: Slider(
                                            value: widget.tile.volume.clamp(0.0, 2.5),
                                            min: 0.0,
                                            max: 2.5,
                                            onChanged: (v) async {
                                              await widget.tile.setVolume(v);
                                              if (widget.tile.isMuted && v > 0) {
                                                await widget.tile.toggleMute();
                                                widget.onMuteChanged();
                                              }
                                              if (mounted) setState(() {});
                                              _resetHideTimer();
                                            },
                                          ),
                                        ),
                                      ),
                                      Text(
                                        '%${(widget.tile.volume * 100).toInt()}',
                                        style: TextStyle(
                                          color: widget.tile.volume > 1.0 ? Colors.orangeAccent : Colors.cyanAccent,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      InkWell(
                                        onTap: () async {
                                          final next = widget.tile.volume >= 2.0 ? 1.0 : 2.0;
                                          await widget.tile.setVolume(next);
                                          if (widget.tile.isMuted) {
                                            await widget.tile.toggleMute();
                                            widget.onMuteChanged();
                                          }
                                          if (mounted) setState(() {});
                                          _resetHideTimer();
                                        },
                                        borderRadius: BorderRadius.circular(6),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: widget.tile.volume >= 1.8 ? Colors.orange.withValues(alpha: 0.3) : Colors.white12,
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                              color: widget.tile.volume >= 1.8 ? Colors.orangeAccent : Colors.white24,
                                            ),
                                          ),
                                          child: Text(
                                            widget.tile.volume >= 1.8 ? '🔥 %200' : '⚡ Boost',
                                            style: TextStyle(
                                              color: widget.tile.volume >= 1.8 ? Colors.orangeAccent : Colors.white70,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                              ],
                              // Fit Mode Toggle
                              ElevatedButton.icon(
                                onPressed: _toggleFitMode,
                                icon: Icon(
                                  _fitMode == RTCVideoViewObjectFit.RTCVideoViewObjectFitContain
                                      ? Icons.fit_screen
                                      : Icons.aspect_ratio,
                                  size: 18,
                                ),
                                label: Text(
                                  _fitMode == RTCVideoViewObjectFit.RTCVideoViewObjectFitContain
                                      ? 'Sığdır'
                                      : 'Doldur',
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.black.withValues(alpha: 0.6),
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(color: Colors.white24),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                              const SizedBox(width: 10),
                              // Exit Fullscreen Button
                              IconButton.filledTonal(
                                onPressed: _exitFullscreen,
                                icon: const Icon(Icons.fullscreen_exit, color: Colors.white, size: 22),
                                tooltip: 'Tam Ekrandan Çık (Esc)',
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.black.withValues(alpha: 0.6),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
