// lib/features/medicine/presentation/screens/medicine_detail_screen.dart
// ============================================================
// MEDICINE DETAIL SCREEN — with Auto Text-to-Speech
//
// ORIGINAL FEATURES:
// • Auto-reads every info card aloud on screen open (no user action needed)
// • 3-second pause between each card while reading
// • Volume icon in app-bar shows live speaking state (animated pulse)
// • Tap volume icon → stop/restart reading
// • Reading stops automatically when user leaves the screen
//
// NEW FEATURE (added):
// • "Add Reminder" FAB at the bottom centre of the screen
// • Tapping it stops TTS and navigates to AddReminderScreen
// • Medicine Name, Dosage, and Instructions fields are pre-filled
//   automatically — user only needs to set the reminder time(s)
// ============================================================
// ignore_for_file: deprecated_member_use, curly_braces_in_flow_control_structures
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../../domain/entities/medicine.dart';
// ── NEW IMPORT: navigate to AddReminderScreen ────────────────
import '../../../reminders/presentation/screens/add_reminder_screen.dart';

// ─── TTS state enum ──────────────────────────────────────────
enum _TtsState { playing, stopped }

class MedicineDetailScreen extends StatefulWidget {
  final Medicine medicine;
  final String? scannedText;
  const MedicineDetailScreen({
    super.key,
    required this.medicine,
    this.scannedText,
  });
  @override
  State<MedicineDetailScreen> createState() => _MedicineDetailScreenState();
}

class _MedicineDetailScreenState extends State<MedicineDetailScreen>
    with SingleTickerProviderStateMixin {
  // ── TTS engine ───────────────────────────────────────────────
  final FlutterTts _flutterTts = FlutterTts();
  _TtsState _ttsState = _TtsState.stopped;
  // Tracks whether the sequential reading loop is still running
  bool _readingActive = false;
  // ── Pulse animation for the volume icon ─────────────────────
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  // ── Build ordered list of segments to read ──────────────────
  List<_ReadSegment> get _readSegments {
    final m = widget.medicine;
    final segments = <_ReadSegment>[];
    // Introduction
    segments.add(_ReadSegment(
      cardTitle: null, // intro — no card header
      text:
          'Medicine details for ${m.name}. Generic name: ${m.genericName}. '
          'Manufactured by ${m.manufacturer}.',
    ));
    if (m.description != null)
      segments.add(_ReadSegment(
        cardTitle: 'Description',
        text: m.description!,
      ));
    if (m.uses != null)
      segments.add(_ReadSegment(
        cardTitle: 'Uses and Indications',
        text: m.uses!,
      ));
    if (m.dosageInfo != null)
      segments.add(_ReadSegment(
        cardTitle: 'Dosage Instructions',
        text: m.dosageInfo!,
      ));
    if (m.sideEffects != null)
      segments.add(_ReadSegment(
        cardTitle: 'Side Effects',
        text: m.sideEffects!,
      ));
    if (m.precautions != null)
      segments.add(_ReadSegment(
        cardTitle: 'Precautions',
        text: m.precautions!,
      ));
    if (m.storageInstructions != null)
      segments.add(_ReadSegment(
        cardTitle: 'Storage Instructions',
        text: m.storageInstructions!,
      ));
    // Closing disclaimer
    segments.add(_ReadSegment(
      cardTitle: null,
      text:
          'This information is for general reference only. '
          'Always consult a licensed pharmacist or doctor before taking any medicine.',
    ));
    return segments;
  }

  // ── Index of the card currently being read (for highlight) ──
  int _activeSegmentIndex = -1;

  @override
  void initState() {
    super.initState();
    // ── Pulse animation setup ─────────────────────────────────
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.25).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    // ── Configure TTS ─────────────────────────────────────────
    _configureTts();
    // ── Auto-start reading after first frame ──────────────────
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startReading();
    });
  }

  Future<void> _configureTts() async {
    await _flutterTts.setLanguage('en-US');
    await _flutterTts.setSpeechRate(0.48); // comfortable listening speed
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
    await _flutterTts.awaitSpeakCompletion(true); // makes speak() awaitable
    _flutterTts.setStartHandler(() {
      if (mounted) setState(() => _ttsState = _TtsState.playing);
    });
    _flutterTts.setCompletionHandler(() {
      if (mounted && !_readingActive) {
        setState(() => _ttsState = _TtsState.stopped);
        _pulseController.stop();
      }
    });
    _flutterTts.setErrorHandler((msg) {
      debugPrint('❌ TTS error: $msg');
      if (mounted) setState(() => _ttsState = _TtsState.stopped);
      _pulseController.stop();
    });
  }

  // ── Sequential reader ─────────────────────────────────────────
  Future<void> _startReading() async {
    if (_readingActive) return; // already running
    _readingActive = true;
    final segments = _readSegments;
    _pulseController.repeat(reverse: true);
    setState(() {
      _ttsState = _TtsState.playing;
      _activeSegmentIndex = 0;
    });
    for (int i = 0; i < segments.length; i++) {
      if (!_readingActive || !mounted) break;
      setState(() => _activeSegmentIndex = i);
      final label =
          segments[i].cardTitle != null ? '${segments[i].cardTitle}. ' : '';
      final utterance = '$label${segments[i].text}';
      // Speak — awaits until utterance finishes (awaitSpeakCompletion = true)
      await _flutterTts.speak(utterance);
      if (!_readingActive || !mounted) break;
      // 3-second pause between cards (skip after last segment)
      if (i < segments.length - 1) {
        await Future.delayed(const Duration(seconds: 3));
      }
    }
    // Reading loop ended naturally
    if (mounted) {
      setState(() {
        _ttsState = _TtsState.stopped;
        _activeSegmentIndex = -1;
        _readingActive = false;
      });
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  Future<void> _stopReading() async {
    _readingActive = false;
    await _flutterTts.stop();
    if (mounted) {
      setState(() {
        _ttsState = _TtsState.stopped;
        _activeSegmentIndex = -1;
      });
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  // ── Volume button handler ─────────────────────────────────────
  Future<void> _toggleTts() async {
    if (_ttsState == _TtsState.playing) {
      await _stopReading();
    } else {
      await _startReading();
    }
  }

  @override
  void dispose() {
    _readingActive = false;
    _flutterTts.stop();
    _pulseController.dispose();
    super.dispose();
  }

  // ════════════════════════════════════════════════════════════
  // ── NEW METHOD: Navigate to Add Reminder with pre-filled data ─
  // ════════════════════════════════════════════════════════════
  //
  // Field mapping:
  //   widget.medicine.name              → medicineName
  //   strength + " " + dosageForm       → dosage (e.g. "250mg Tablet")
  //   first sentence of dosageInfo      → instructions (optional)
  //
  void _navigateToAddReminder() {
    // Stop TTS so it does not continue playing in the background
    if (_ttsState == _TtsState.playing) _stopReading();

    final m = widget.medicine;

    // Build dosage string e.g. "250mg Tablet"
    final dosageParts = <String>[
      if (m.strength != null && m.strength!.trim().isNotEmpty)
        m.strength!.trim(),
      if (m.dosageForm != null && m.dosageForm!.trim().isNotEmpty)
        m.dosageForm!.trim(),
    ];
    final dosageString = dosageParts.join(' ');

    // Build instructions hint from the first sentence of dosageInfo
    // (capped at 120 chars so it fits neatly in the field)
    String? instructionsHint;
    if (m.dosageInfo != null && m.dosageInfo!.trim().isNotEmpty) {
      final info = m.dosageInfo!.trim();
      final dotIdx = info.indexOf('.');
      if (dotIdx != -1 && dotIdx < 120) {
        instructionsHint = info.substring(0, dotIdx + 1);
      } else if (info.length <= 120) {
        instructionsHint = info;
      } else {
        instructionsHint = '${info.substring(0, 120).trimRight()}…';
      }
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddReminderScreen(
          medicineName: m.name,
          dosage: dosageString.isEmpty ? null : dosageString,
          instructions: instructionsHint, // NEW param — see add_reminder_screen.dart
        ),
      ),
    );
  }
  // ════════════════════════════════════════════════════════════

  // ── UI ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final medicine = widget.medicine;
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: CustomScrollView(
        slivers: [
          // ── App bar with medicine name + volume button ────────
          SliverAppBar(
            expandedHeight: 180,
            pinned: true,
            backgroundColor: Colors.green[700],
            actions: [
              // ── Volume icon ──────────────────────────────────
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Center(
                  child: AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      final isPlaying = _ttsState == _TtsState.playing;
                      return Transform.scale(
                        scale: isPlaying ? _pulseAnimation.value : 1.0,
                        child: child,
                      );
                    },
                    child: IconButton(
                      tooltip: _ttsState == _TtsState.playing
                          ? 'Stop reading'
                          : 'Read aloud',
                      icon: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: Icon(
                          _ttsState == _TtsState.playing
                              ? Icons.volume_up_rounded
                              : Icons.volume_off_rounded,
                          key: ValueKey(_ttsState),
                          color: _ttsState == _TtsState.playing
                              ? Colors.yellowAccent
                              : Colors.white70,
                          size: 28,
                        ),
                      ),
                      onPressed: _toggleTts,
                    ),
                  ),
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                medicine.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Colors.green[800]!, Colors.green[500]!],
                  ),
                ),
                child: const Center(
                  child: Icon(Icons.medication, size: 72, color: Colors.white24),
                ),
              ),
            ),
          ),

          // ── "Now reading" status bar ─────────────────────────
          SliverToBoxAdapter(
            child: AnimatedCrossFade(
              firstChild: _NowReadingBanner(
                segmentTitle: _activeSegmentIndex >= 0 &&
                        _activeSegmentIndex < _readSegments.length
                    ? (_readSegments[_activeSegmentIndex].cardTitle ??
                        'Introduction')
                    : '',
              ),
              secondChild: const SizedBox.shrink(),
              crossFadeState: _ttsState == _TtsState.playing
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
              duration: const Duration(milliseconds: 300),
            ),
          ),

          // ── Main content ──────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Quick info chips
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (medicine.dosageForm != null)
                        _chip(Icons.medication_liquid,
                            medicine.dosageForm!, Colors.blue),
                      if (medicine.strength != null)
                        _chip(Icons.scale, medicine.strength!, Colors.purple),
                      _chip(Icons.category, medicine.category, Colors.teal),
                      if (medicine.isCommon)
                        _chip(Icons.star, 'Common', Colors.amber),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── Generic Name ─────────────────────────────
                  _infoCard(
                    segmentIndex: 0, // intro segment covers name + generic + mfr
                    title: '🔬 Generic Name',
                    content: medicine.genericName,
                    bgColor: Colors.blue[50]!,
                  ),

                  // ── Manufacturer ─────────────────────────────
                  _infoCard(
                    segmentIndex: 0,
                    title: '🏭 Manufacturer',
                    content: medicine.manufacturer,
                    bgColor: Colors.grey[100]!,
                  ),

                  // ── Description ──────────────────────────────
                  if (medicine.description != null)
                    _infoCard(
                      segmentIndex: _segmentIndexFor('Description'),
                      title: '📋 Description',
                      content: medicine.description!,
                    ),

                  // ── Uses ─────────────────────────────────────
                  if (medicine.uses != null)
                    _infoCard(
                      segmentIndex: _segmentIndexFor('Uses and Indications'),
                      title: '✅ Uses / Indications',
                      content: medicine.uses!,
                      bgColor: Colors.green[50]!,
                    ),

                  // ── Dosage ───────────────────────────────────
                  if (medicine.dosageInfo != null)
                    _infoCard(
                      segmentIndex: _segmentIndexFor('Dosage Instructions'),
                      title: '💊 Dosage Instructions',
                      content: medicine.dosageInfo!,
                      bgColor: Colors.indigo[50]!,
                    ),

                  // ── Side Effects ─────────────────────────────
                  if (medicine.sideEffects != null)
                    _infoCard(
                      segmentIndex: _segmentIndexFor('Side Effects'),
                      title: '⚠️Side Effects',
                      content: medicine.sideEffects!,
                      bgColor: Colors.orange[50]!,
                    ),

                  // ── Precautions ──────────────────────────────
                  if (medicine.precautions != null)
                    _infoCard(
                      segmentIndex: _segmentIndexFor('Precautions'),
                      title: '🚨 Precautions',
                      content: medicine.precautions!,
                      bgColor: Colors.red[50]!,
                    ),

                  // ── Storage ──────────────────────────────────
                  if (medicine.storageInstructions != null)
                    _infoCard(
                      segmentIndex: _segmentIndexFor('Storage Instructions'),
                      title: '🌡️Storage Instructions',
                      content: medicine.storageInstructions!,
                      bgColor: Colors.cyan[50]!,
                    ),

                  const SizedBox(height: 24),

                  // ── Medical disclaimer ────────────────────────
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.yellow[100],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.yellow[700]!),
                    ),
                    child: const Text(
                      '\n\nThis information is for general reference only. '
                      'Always consult a licensed pharmacist or doctor before '
                      'taking any medicine.',
                      style: TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                  ),

                  // ── Bottom padding so the FAB never covers content ──────
                  // ── (NEW — added because we placed a FAB at centerFloat) ─
                  const SizedBox(height: 90),
                ],
              ),
            ),
          ),
        ],
      ),

      // ════════════════════════════════════════════════════════
      // ── NEW: "Add Reminder" Floating Action Button ────────
      //
      // • Green pill-shaped button pinned at the bottom centre
      // • Icon: alarm_add_rounded (bell with plus sign)
      // • Calls _navigateToAddReminder() which pushes
      //   AddReminderScreen with all 3 fields pre-populated
      // ════════════════════════════════════════════════════════
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _navigateToAddReminder,
        backgroundColor: Colors.green[700],
        foregroundColor: Colors.white,
        elevation: 4,
        icon: const Icon(Icons.alarm_add_rounded),
        label: const Text(
          'Add Reminder',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  // ── Helper: find the index of a segment by its card title ───
  int _segmentIndexFor(String cardTitle) {
    final segs = _readSegments;
    for (int i = 0; i < segs.length; i++) {
      if (segs[i].cardTitle == cardTitle) return i;
    }
    return -1;
  }

  // ── Info card widget — highlights when being read ────────────
  Widget _infoCard({
    required int segmentIndex,
    required String title,
    required String content,
    Color bgColor = Colors.white,
  }) {
    final isActive =
        segmentIndex != -1 && _activeSegmentIndex == segmentIndex;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isActive ? Colors.green[100] : bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive ? Colors.green[600]! : Colors.grey[200]!,
          width: isActive ? 2.0 : 1.0,
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: Colors.green.withOpacity(0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                )
              ]
            : [],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                // Small speaker icon on the active card
                if (isActive)
                  const Icon(Icons.graphic_eq_rounded,
                      color: Colors.green, size: 20),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              content,
              style: const TextStyle(fontSize: 14, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }

  // ── Chip widget ──────────────────────────────────────────────
  Widget _chip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
                fontSize: 12, color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// ── Data class for a TTS segment ────────────────────────────────
class _ReadSegment {
  final String? cardTitle; // null = intro / outro (no card)
  final String text;
  const _ReadSegment({required this.cardTitle, required this.text});
}

// ── "Now reading" animated banner ───────────────────────────────
class _NowReadingBanner extends StatelessWidget {
  final String segmentTitle;
  const _NowReadingBanner({required this.segmentTitle});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.green[700],
      child: Row(
        children: [
          const Icon(Icons.volume_up_rounded, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              segmentTitle.isEmpty
                  ? 'Reading medicine information…'
                  : 'Now reading: $segmentTitle',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}