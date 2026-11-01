import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../services/location_service.dart';

/// A smart address input field with:
///
/// 1. **GPS button** – Detects location, reverse-geocodes → human-readable address.
/// 2. **Loading indicator** – Shown on the field while GPS is fetching or
///    suggestions are being searched (spinner replaces GPS button + linear bar on field).
/// 3. **Autocomplete dropdown** – After ≥ 3 chars typed, shows suggestions
///    filtered to 10 km around Melapalayam.
/// 4. **Clear chip** – Appears below the field when text is present; one tap
///    wipes the address and coordinates.
class LocationAddressField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final IconData leadingIcon;
  final Color accentColor;
  final String? Function(String?)? validator;
  final void Function(double lat, double lng)? onLocationPicked;
  /// Called when the address is cleared via the clear chip.
  final VoidCallback? onCleared;

  const LocationAddressField({
    super.key,
    required this.controller,
    required this.label,
    this.leadingIcon = Icons.location_on,
    this.accentColor = const Color(0xFF10B981),
    this.validator,
    this.onLocationPicked,
    this.onCleared,
  });

  @override
  State<LocationAddressField> createState() => _LocationAddressFieldState();
}

class _LocationAddressFieldState extends State<LocationAddressField>
    with SingleTickerProviderStateMixin {
  final FocusNode _focusNode = FocusNode();
  final LayerLink _layerLink = LayerLink();

  List<PlaceSuggestion> _suggestions = [];
  bool _isLoadingGps = false;
  bool _isLoadingSuggestions = false;
  bool _hasText = false;

  OverlayEntry? _overlayEntry;
  Timer? _debounce;

  // For shimmer animation on the loading bar
  late final AnimationController _shimmerCtrl;
  late final Animation<double> _shimmerAnim;

  @override
  void initState() {
    super.initState();
    _hasText = widget.controller.text.isNotEmpty;
    widget.controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);

    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    _shimmerAnim = Tween<double>(begin: -1.5, end: 1.5).animate(
      CurvedAnimation(parent: _shimmerCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _removeOverlay();
    widget.controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _shimmerCtrl.dispose();
    super.dispose();
  }

  // ─── Text change → debounced search ────────────────────────────────────────

  void _onTextChanged() {
    final text = widget.controller.text;
    final hadText = _hasText;
    final hasText = text.isNotEmpty;

    _debounce?.cancel();

    if (text.trim().length < 3) {
      _clearSuggestions();
      if (hadText != hasText) setState(() => _hasText = hasText);
      return;
    }

    if (hadText != hasText) setState(() => _hasText = hasText);

    _debounce = Timer(const Duration(milliseconds: 450), () {
      _fetchSuggestions(text);
    });
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      Future.delayed(const Duration(milliseconds: 200), () {
        _clearSuggestions();
      });
    }
  }

  Future<void> _fetchSuggestions(String query) async {
    if (!mounted) return;
    setState(() => _isLoadingSuggestions = true);

    final results = await LocationService.searchPlaces(query);

    if (!mounted) return;
    setState(() {
      _suggestions = results;
      _isLoadingSuggestions = false;
    });

    if (results.isNotEmpty) {
      _showOverlay();
    } else {
      _removeOverlay();
    }
  }

  void _clearSuggestions() {
    if (!mounted) return;
    setState(() => _suggestions = []);
    _removeOverlay();
  }

  // ─── Clear address ──────────────────────────────────────────────────────────

  void _clearAddress() {
    widget.controller.clear();
    _clearSuggestions();
    setState(() => _hasText = false);
    widget.onCleared?.call();
    _focusNode.unfocus();
  }

  // ─── GPS detection ──────────────────────────────────────────────────────────

  Future<void> _detectGps() async {
    _clearSuggestions();
    setState(() => _isLoadingGps = true);

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permission denied');
        }
      }
      if (permission == LocationPermission.deniedForever) {
        throw Exception('Permission permanently denied. Enable in Settings.');
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // Reverse geocode → human-readable address
      final address = await LocationService.reverseGeocode(
        position.latitude,
        position.longitude,
      );

      if (!mounted) return;

      widget.controller.text = address;
      setState(() => _hasText = address.isNotEmpty);
      widget.onLocationPicked?.call(position.latitude, position.longitude);

      _showGpsSuccessSnack(address);
    } catch (e) {
      if (!mounted) return;
      _showErrorSnack('GPS Error: $e');
    } finally {
      if (mounted) setState(() => _isLoadingGps = false);
    }
  }

  void _showGpsSuccessSnack(String address) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: widget.accentColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
        duration: const Duration(seconds: 3),
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'GPS location captured!',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    address,
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showErrorSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
      ),
    );
  }

  // ─── Overlay dropdown ───────────────────────────────────────────────────────

  void _showOverlay() {
    _removeOverlay();
    final overlay = Overlay.of(context);
    _overlayEntry = _buildOverlayEntry();
    overlay.insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  OverlayEntry _buildOverlayEntry() {
    return OverlayEntry(
      builder: (context) => Positioned(
        width: _getFieldWidth(),
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 58),
          child: Material(
            elevation: 10,
            borderRadius: BorderRadius.circular(12),
            color: const Color(0xFF1E293B),
            child: _buildDropdownContent(),
          ),
        ),
      ),
    );
  }

  double _getFieldWidth() {
    final box = context.findRenderObject() as RenderBox?;
    return box?.size.width ?? 300;
  }

  Widget _buildDropdownContent() {
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 260),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ListView.separated(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            itemCount: _suggestions.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, color: Color(0xFF334155)),
            itemBuilder: (context, index) {
              final s = _suggestions[index];
              return InkWell(
                onTap: () => _selectSuggestion(s),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 11),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.place_rounded,
                          color: widget.accentColor, size: 16),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.displayName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (s.fullAddress != s.displayName) ...[
                              const SizedBox(height: 2),
                              Text(
                                s.fullAddress,
                                style: const TextStyle(
                                    color: Colors.white38, fontSize: 11),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _selectSuggestion(PlaceSuggestion suggestion) {
    widget.controller.text = suggestion.fullAddress;
    setState(() => _hasText = true);
    widget.onLocationPicked?.call(suggestion.lat, suggestion.lng);
    _clearSuggestions();
    _focusNode.unfocus();
  }

  // ─── Loading shimmer bar ────────────────────────────────────────────────────

  Widget _buildLoadingBar() {
    final color = widget.accentColor;
    return AnimatedBuilder(
      animation: _shimmerAnim,
      builder: (context, _) {
        return ClipRRect(
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(10),
            bottomRight: Radius.circular(10),
          ),
          child: Container(
            height: 3,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                stops: [
                  (_shimmerAnim.value - 0.4).clamp(0.0, 1.0),
                  (_shimmerAnim.value).clamp(0.0, 1.0),
                  (_shimmerAnim.value + 0.4).clamp(0.0, 1.0),
                ],
                colors: [
                  color.withValues(alpha: 0.08),
                  color.withValues(alpha: 0.85),
                  color.withValues(alpha: 0.08),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ─── Suffix icon logic ──────────────────────────────────────────────────────

  Widget _buildSuffixIcon() {
    if (_isLoadingGps) {
      // GPS searching: spinning indicator
      return Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: widget.accentColor,
          ),
        ),
      );
    }

    if (_isLoadingSuggestions) {
      // Text search: smaller spinner
      return Padding(
        padding: const EdgeInsets.all(14),
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: widget.accentColor.withValues(alpha: 0.6),
          ),
        ),
      );
    }

    // Default: GPS chip button
    return Tooltip(
      message: 'Use current GPS location',
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: _detectGps,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: widget.accentColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: widget.accentColor.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.my_location, color: widget.accentColor, size: 14),
                const SizedBox(width: 3),
                Text(
                  'GPS',
                  style: TextStyle(
                    color: widget.accentColor,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isLoading = _isLoadingGps || _isLoadingSuggestions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Field + loading bar stack ─────────────────────────────────────────
        CompositedTransformTarget(
          link: _layerLink,
          child: Stack(
            children: [
              // The text input field
              TextFormField(
                controller: widget.controller,
                focusNode: _focusNode,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: widget.label,
                  labelStyle:
                      const TextStyle(color: Colors.white60, fontSize: 13),
                  prefixIcon: Icon(widget.leadingIcon,
                      color: widget.accentColor, size: 20),
                  suffixIcon: _buildSuffixIcon(),
                  filled: true,
                  fillColor: const Color(0xFF1E293B),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                        color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                        color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: widget.accentColor),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        const BorderSide(color: Colors.redAccent),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        const BorderSide(color: Colors.redAccent),
                  ),
                ),
                validator: widget.validator,
              ),

              // Animated loading shimmer bar — sits at bottom of field
              if (isLoading)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _buildLoadingBar(),
                ),

              // Loading status label — sits inside field top-right area
              if (isLoading)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Container(
                      height: 56,
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: widget.accentColor
                                  .withValues(alpha: 0.7),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _isLoadingGps
                                ? 'Getting GPS location…'
                                : 'Searching places…',
                            style: TextStyle(
                              color: widget.accentColor
                                  .withValues(alpha: 0.85),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),

        // ── Clear chip — shown when field has content and not loading ─────────
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SizeTransition(sizeFactor: anim, child: child),
          ),
          child: (_hasText && !isLoading)
              ? Padding(
                  key: const ValueKey('clear_chip'),
                  padding: const EdgeInsets.only(top: 6, left: 2),
                  child: GestureDetector(
                    onTap: _clearAddress,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.cancel_rounded,
                          size: 13,
                          color: Colors.white38,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Clear address',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            decoration: TextDecoration.underline,
                            decorationColor: Colors.white24,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : const SizedBox.shrink(key: ValueKey('no_clear')),
        ),
      ],
    );
  }
}
