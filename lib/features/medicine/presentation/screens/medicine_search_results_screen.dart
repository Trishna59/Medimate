// lib/features/medicine/presentation/screens/medicine_search_results_screen.dart
// ============================================
// SEARCH RESULTS — Shows matched medicines from scan
// ✅ ENHANCED: Live search bar + full Text-to-Speech integration
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../../domain/entities/medicine.dart';
import 'medicine_detail_screen.dart';

// ─── TTS playback state ───────────────────────────────────────
enum _TtsState { playing, stopped }

class MedicineSearchResultsScreen extends StatefulWidget {
  final List<Medicine> medicines;
  final String scannedText;

  const MedicineSearchResultsScreen({
    super.key,
    required this.medicines,
    required this.scannedText,
  });

  @override
  State<MedicineSearchResultsScreen> createState() =>
      _MedicineSearchResultsScreenState();
}

class _MedicineSearchResultsScreenState
    extends State<MedicineSearchResultsScreen>
    with SingleTickerProviderStateMixin {
  // ── Search ─────────────────────────────────────────────────
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  List<Medicine> get _filteredMedicines {
    if (_searchQuery.isEmpty) return widget.medicines;
    final q = _searchQuery.toLowerCase();
    return widget.medicines.where((m) {
      return m.name.toLowerCase().contains(q) ||
          m.genericName.toLowerCase().contains(q) ||
          m.manufacturer.toLowerCase().contains(q);
    }).toList();
  }

  // ── TTS ────────────────────────────────────────────────────
  final FlutterTts _flutterTts = FlutterTts();
  _TtsState _ttsState = _TtsState.stopped;
  bool _readingActive = false;

  // Index in the *full* (unfiltered) list being read aloud right now
  int _speakingIndex = -1;
  _TtsPhase _speakingPhase = _TtsPhase.intro;

  // ── Pulse animation for the volume FAB ─────────────────────
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  // ── Best-match medicine (highest confidence) ───────────────
  Medicine? get _bestMatch {
    if (widget.medicines.isEmpty) return null;
    return widget.medicines.reduce((a, b) =>
        a.calculateMatchConfidence(widget.scannedText) >=
                b.calculateMatchConfidence(widget.scannedText)
            ? a
            : b);
  }

  // ── Build TTS script for all results ───────────────────────
  List<_TtsEntry> get _ttsScript {
    final entries = <_TtsEntry>[];

    // ── 1. Result count announcement ──────────────────────────
    entries.add(_TtsEntry(
      index: -1,
      phase: _TtsPhase.intro,
      text: 'Medicine search complete. '
          'Found ${widget.medicines.length} '
          '${widget.medicines.length == 1 ? 'match' : 'matches'} '
          'for your scanned medicine.',
    ));

    // ── 2. Safety & prescription instructions ─────────────────
    entries.add(_TtsEntry(
      index: -1,
      phase: _TtsPhase.warning,
      text: 'Important safety notice. '
          'Before selecting or purchasing any medicine from this list, '
          'please make sure you have a proper prescription from a licensed doctor. '
          'Do not self-medicate. '
          'Always confirm the medicine name, dosage, and strength '
          'with your doctor or a qualified pharmacist. '
          'Different manufacturers may produce the same medicine under different brand names. '
          'The match percentage shown is based on the scanned label only '
          'and is not a substitute for professional medical advice.',
    ));

    // ── 3. Transition to list ──────────────────────────────────
    entries.add(_TtsEntry(
      index: -1,
      phase: _TtsPhase.intro,
      text: 'I will now read the list of matching medicines '
          'along with their generic names and manufacturers. '
          'Tap any medicine card on screen to hear its full details.',
    ));

    // ── 4. One entry per medicine ──────────────────────────────
    for (int i = 0; i < widget.medicines.length; i++) {
      final m = widget.medicines[i];
      final pct = (m.calculateMatchConfidence(widget.scannedText) * 100)
          .toStringAsFixed(0);
      entries.add(_TtsEntry(
        index: i,
        phase: _TtsPhase.medicine,
        text: 'Number ${i + 1}. ${m.name}. '
            'Generic name: ${m.genericName}. '
            'Manufactured by ${m.manufacturer}. '
            'Match: $pct percent.',
      ));
    }

    // ── 5. Best-match recommendation ──────────────────────────
    final best = _bestMatch;
    if (best != null) {
      entries.add(_TtsEntry(
        index: -1,
        phase: _TtsPhase.recommendation,
        text: 'Suggestion: Based on the scan, '
            'the closest matching medicine in this list is '
            '${best.name} by ${best.manufacturer}. '
            'However, you must verify this with your doctor '
            'before taking any medicine. '
            'Tap the medicine card to hear its full details.',
      ));
    }

    return entries;
  }

  // ── Lifecycle ──────────────────────────────────────────────
  @override
  void initState() {
    super.initState();

    // Pulse animation
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.22).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _configureTts();

    // Auto-start reading after first frame (mirrors MedicineDetailScreen)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.medicines.isNotEmpty) _startReading();
    });

    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim());
    });
  }

  Future<void> _configureTts() async {
    await _flutterTts.setLanguage('en-US');
    await _flutterTts.setSpeechRate(0.48);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
    await _flutterTts.awaitSpeakCompletion(true);

    _flutterTts.setStartHandler(() {
      if (mounted) setState(() => _ttsState = _TtsState.playing);
    });

    _flutterTts.setCompletionHandler(() {
      if (mounted && !_readingActive) {
        setState(() {
          _ttsState = _TtsState.stopped;
          _speakingIndex = -1;
        });
        _pulseController.stop();
      }
    });

    _flutterTts.setErrorHandler((msg) {
      debugPrint('❌ TTS error: $msg');
      if (mounted) {
        setState(() {
          _ttsState = _TtsState.stopped;
          _speakingIndex = -1;
        });
        _pulseController.stop();
      }
    });
  }

  // ── Navigate to detail — stops TTS first, then pushes ──────
  /// Called from every card tap. Kills the reading loop and waits for
  /// the engine to go silent before pushing MedicineDetailScreen so the
  /// two TTS streams never overlap.
  Future<void> _navigateToDetail(Medicine medicine) async {
    // 1. Kill the loop flag immediately so the for-loop exits on next check
    _readingActive = false;

    // 2. Hard-stop the TTS engine (awaited so audio cuts before push)
    await _flutterTts.stop();

    // 3. Reset UI state
    if (mounted) {
      setState(() {
        _ttsState = _TtsState.stopped;
        _speakingIndex = -1;
      });
      _pulseController.stop();
      _pulseController.reset();
    }

    // 4. Now push — detail screen starts its own clean TTS session
    if (mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MedicineDetailScreen(
            medicine: medicine,
            scannedText: widget.scannedText,
          ),
        ),
      );
      // When the user pops back to this screen do NOT auto-restart TTS —
      // let them press the FAB or AppBar button if they want to re-read.
    }
  }

  // ── TTS controls ───────────────────────────────────────────
  Future<void> _startReading() async {
    if (_readingActive) return;
    _readingActive = true;
    _pulseController.repeat(reverse: true);
    setState(() {
      _ttsState = _TtsState.playing;
      _speakingIndex = -1;
    });

    final script = _ttsScript;
    for (int i = 0; i < script.length; i++) {
      if (!_readingActive || !mounted) break;
      setState(() {
        _speakingIndex = script[i].index;
        _speakingPhase = script[i].phase;
      });
      await _flutterTts.speak(script[i].text);
      if (!_readingActive || !mounted) break;
      if (i < script.length - 1) {
        await Future.delayed(const Duration(milliseconds: 700));
      }
    }

    if (mounted) {
      _readingActive = false;
      setState(() {
        _ttsState = _TtsState.stopped;
        _speakingIndex = -1;
        _speakingPhase = _TtsPhase.intro;
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
        _speakingIndex = -1;
        _speakingPhase = _TtsPhase.intro;
      });
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  void _toggleTts() {
    if (_ttsState == _TtsState.playing) {
      _stopReading();
    } else {
      _startReading();
    }
  }

  @override
  void dispose() {
    _readingActive = false;
    _flutterTts.stop();
    _pulseController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final filtered = _filteredMedicines;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Medicine Search Results'),
        actions: [
          // ── Pulsing volume icon in the AppBar corner ──────
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _ttsState == _TtsState.playing
                      ? _pulseAnimation.value
                      : 1.0,
                  child: child,
                );
              },
              child: IconButton(
                tooltip: _ttsState == _TtsState.playing
                    ? 'Stop reading aloud'
                    : 'Read results aloud',
                icon: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Icon(
                    _ttsState == _TtsState.playing
                        ? Icons.volume_up_rounded
                        : Icons.volume_off_rounded,
                    key: ValueKey(_ttsState),
                    color: _ttsState == _TtsState.playing
                        ? Colors.blue[700]
                        : null,
                    size: 28,
                  ),
                ),
                onPressed: _toggleTts,
              ),
            ),
          ),
        ],
      ),
      body: widget.medicines.isEmpty
          ? _buildNoResultsView(context)
          : Column(
              children: [
                // ── Info banner ───────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  color: Colors.blue[50],
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue[700]),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Found ${widget.medicines.length} '
                          '${widget.medicines.length == 1 ? 'match' : 'matches'}. '
                          'Tap to view details.',
                          style: TextStyle(color: Colors.blue[900]),
                        ),
                      ),
                      // Mini TTS status chip
                      if (_ttsState == _TtsState.playing)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.blue[100],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.spatial_audio_off_rounded,
                                  size: 14, color: Colors.blue[700]),
                              const SizedBox(width: 4),
                              Text(
                                'Reading…',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.blue[700],
                                    fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),

                // ── TTS hint strip (shown while playing) ─────
                AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  child: _ttsState == _TtsState.playing
                      ? Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          color: Colors.blue[700],
                          child: Row(
                            children: [
                              const Icon(Icons.record_voice_over_rounded,
                                  color: Colors.white, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _speakingIndex >= 0 &&
                                          _speakingIndex <
                                              widget.medicines.length &&
                                          _speakingPhase == _TtsPhase.medicine
                                      ? 'Now reading: '
                                          '${widget.medicines[_speakingIndex].name}'
                                      : _speakingPhase == _TtsPhase.warning
                                          ? '⚠️  Safety notice — please listen carefully'
                                          : _speakingPhase ==
                                                  _TtsPhase.recommendation
                                              ? '💊  Reading suggestion…'
                                              : 'Preparing results…',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              GestureDetector(
                                onTap: _stopReading,
                                child: const Icon(Icons.stop_circle_outlined,
                                    color: Colors.white70, size: 20),
                              ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(),
                ),

                // ── Search bar ───────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search in results…',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded),
                              onPressed: () => _searchController.clear(),
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.grey[100],
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),

                // ── Filter result count ──────────────────────
                if (_searchQuery.isNotEmpty)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${filtered.length} result${filtered.length == 1 ? '' : 's'} for "$_searchQuery"',
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ),
                  ),

                // ── Results list ─────────────────────────────
                Expanded(
                  child: filtered.isEmpty
                      ? _buildNoFilterResultsView()
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final medicine = filtered[index];
                            // Rank = position in the original full list
                            final originalRank =
                                widget.medicines.indexOf(medicine) + 1;
                            final isSpeaking =
                                _speakingIndex == originalRank - 1;
                            return _MedicineResultCard(
                              medicine: medicine,
                              rank: originalRank,
                              scannedText: widget.scannedText,
                              isSpeaking: isSpeaking,
                              onTap: () => _navigateToDetail(medicine),
                            );
                          },
                        ),
                ),
              ],
            ),

      // ── Floating action: re-read / stop ──────────────────────
      floatingActionButton: widget.medicines.isNotEmpty
          ? AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _ttsState == _TtsState.playing
                      ? _pulseAnimation.value
                      : 1.0,
                  child: child,
                );
              },
              child: FloatingActionButton.extended(
                onPressed: _toggleTts,
                backgroundColor: _ttsState == _TtsState.playing
                    ? Colors.red[400]
                    : Colors.blue[700],
                icon: Icon(
                  _ttsState == _TtsState.playing
                      ? Icons.stop_rounded
                      : Icons.volume_up_rounded,
                  color: Colors.white,
                ),
                label: Text(
                  _ttsState == _TtsState.playing
                      ? 'Stop Reading'
                      : 'Read Results',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            )
          : null,
    );
  }

  // ── Empty state when filter finds nothing ─────────────────
  Widget _buildNoFilterResultsView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded, size: 72, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'No results for "$_searchQuery"',
            style: TextStyle(color: Colors.grey[600]),
          ),
          TextButton(
            onPressed: () => _searchController.clear(),
            child: const Text('Clear search'),
          ),
        ],
      ),
    );
  }

  // ── No scan results at all ────────────────────────────────
  Widget _buildNoResultsView(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 100, color: Colors.grey[300]),
            const SizedBox(height: 24),
            Text(
              'No Medicines Found',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'We couldn\'t find any medicines matching the scanned text.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            Card(
              color: Colors.orange[50],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.lightbulb_outline,
                            color: Colors.orange[700]),
                        const SizedBox(width: 8),
                        Text(
                          'Tips for better results:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.orange[900],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '• Ensure good lighting\n'
                      '• Capture the medicine name clearly\n'
                      '• Avoid blurry images\n'
                      '• Try scanning the label area',
                      style: TextStyle(color: Colors.orange[800]),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.camera_alt),
              label: const Text('Scan Again'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Result card ───────────────────────────────────────────────
class _MedicineResultCard extends StatelessWidget {
  final Medicine medicine;
  final int rank;
  final String scannedText;
  final bool isSpeaking;

  /// Navigation + TTS stop is handled by the parent screen.
  /// The card itself never pushes a route directly.
  final VoidCallback onTap;

  const _MedicineResultCard({
    required this.medicine,
    required this.rank,
    required this.scannedText,
    required this.onTap,
    this.isSpeaking = false,
  });

  @override
  Widget build(BuildContext context) {
    final confidence = medicine.calculateMatchConfidence(scannedText);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        // Glow effect when this card is being read aloud
        boxShadow: isSpeaking
            ? [
                BoxShadow(
                  color: Colors.blue.withOpacity(0.35),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ]
            : [],
      ),
      child: Card(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: isSpeaking
              ? const BorderSide(color: Colors.blue, width: 2)
              : BorderSide.none,
        ),
        child: InkWell(
          onTap: onTap,   // ← parent handles TTS stop + navigation
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // ── Rank badge ──────────────────────────────
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: rank == 1
                        ? Colors.green
                        : rank == 2
                            ? Colors.blue
                            : Colors.grey,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '#$rank',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 16),

                // ── Medicine info ───────────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              medicine.name,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                          // Speaking indicator icon
                          if (isSpeaking)
                            const Padding(
                              padding: EdgeInsets.only(left: 6),
                              child: Icon(
                                Icons.spatial_audio_rounded,
                                size: 18,
                                color: Colors.blue,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        medicine.genericName,
                        style:
                            TextStyle(color: Colors.grey[600], fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        medicine.manufacturer,
                        style:
                            TextStyle(color: Colors.grey[500], fontSize: 12),
                      ),
                      const SizedBox(height: 8),

                      // ── Confidence indicator ──────────────
                      Row(
                        children: [
                          Icon(
                            confidence >= 0.8
                                ? Icons.check_circle
                                : Icons.info,
                            size: 14,
                            color: confidence >= 0.8
                                ? Colors.green
                                : Colors.orange,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${(confidence * 100).toStringAsFixed(0)}% match',
                            style: TextStyle(
                              fontSize: 12,
                              color: confidence >= 0.8
                                  ? Colors.green
                                  : Colors.orange,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── TTS phase — drives the live ticker label ──────────────────
enum _TtsPhase { intro, warning, medicine, recommendation }

// ─── Internal model for TTS script entries ─────────────────────
class _TtsEntry {
  /// -1 = narration (intro/warning/recommendation), ≥0 = medicine list index
  final int index;
  final _TtsPhase phase;
  final String text;

  const _TtsEntry({
    required this.index,
    required this.phase,
    required this.text,
  });
}