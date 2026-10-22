import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../models/location_model.dart';
import '../services/api_exception.dart';
import '../services/location_service.dart';
import '../utils/app_theme.dart';
import '../widgets/state_views.dart';

/// Destination search across India. Returns the chosen [LocationModel] to
/// the caller.
class DestinationSearchScreen extends StatefulWidget {
  const DestinationSearchScreen({super.key, this.service, this.near});

  /// Injectable for tests; defaults to the real search service.
  final LocationSearchService? service;

  /// Usually the user's position; nearby places are ranked first.
  final LatLng? near;

  @override
  State<DestinationSearchScreen> createState() =>
      _DestinationSearchScreenState();
}

class _DestinationSearchScreenState extends State<DestinationSearchScreen> {
  late final LocationSearchService _service =
      widget.service ?? LocationSearchService();
  final TextEditingController _controller = TextEditingController();

  /// Long enough to skip intermediate keystrokes, short enough to feel live.
  static const Duration debounceDuration = Duration(milliseconds: 300);

  Timer? _debounce;
  List<LocationModel> _results = const <LocationModel>[];
  bool _isLoading = false;
  bool _hasSearched = false;
  String? _errorMessage;

  /// True while the text is shorter than the geocoder accepts.
  bool _tooShort = false;

  /// True when the backend's geocoder was down and only its short built-in
  /// list answered.
  bool _degraded = false;

  /// The normalised query the current results belong to.
  String? _resultsQuery;

  /// Guards against an earlier slow request overwriting a newer one. Bumped
  /// on every edit, so a reply for text the user has since changed or
  /// cleared is ignored even before the next request starts.
  int _requestId = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    if (widget.service == null) _service.dispose();
    super.dispose();
  }

  static bool _isLongEnough(String query) =>
      query.replaceAll(' ', '').length >= LocationSearchService.minQueryLength;

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final String query = normalizeSearchQuery(value);

    if (!_isLongEnough(query)) {
      _requestId++;
      setState(() {
        _results = const <LocationModel>[];
        _resultsQuery = null;
        _isLoading = false;
        _hasSearched = false;
        _degraded = false;
        _errorMessage = null;
        _tooShort = query.isNotEmpty;
      });
      return;
    }

    // Only spacing or letter case changed: the results already match.
    if (_errorMessage == null &&
        query.toLowerCase() == _resultsQuery?.toLowerCase()) {
      _requestId++;
      if (_isLoading) setState(() => _isLoading = false);
      return;
    }

    _requestId++;
    if (_tooShort) setState(() => _tooShort = false);
    _debounce = Timer(debounceDuration, () => _search(query));
  }

  Future<void> _search(String query) async {
    if (!_isLongEnough(query)) return;
    final int requestId = ++_requestId;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final LocationSearchResult result =
          await _service.search(query, near: widget.near);
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _results = result.places;
        _degraded = result.degraded;
        _resultsQuery = query;
        _isLoading = false;
        _hasSearched = true;
      });
    } on ApiException catch (error) {
      if (!mounted || requestId != _requestId) return;
      _showError(error.message);
    } catch (_) {
      if (!mounted || requestId != _requestId) return;
      _showError('Could not search for that location.');
    }
  }

  /// A failure is never shown as "no results": it gets its own message and
  /// a retry.
  void _showError(String message) {
    setState(() {
      _isLoading = false;
      _hasSearched = true;
      _results = const <LocationModel>[];
      _resultsQuery = null;
      _degraded = false;
      _errorMessage = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Where do you want to go?'),
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: _onQueryChanged,
              onSubmitted: (String value) {
                _debounce?.cancel();
                _search(normalizeSearchQuery(value));
              },
              decoration: InputDecoration(
                hintText: 'Search destination...',
                prefixIcon: const Icon(Icons.search, size: 21),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        tooltip: 'Clear search',
                        onPressed: () {
                          _controller.clear();
                          _onQueryChanged('');
                        },
                      ),
              ),
            ),
          ),
          // Thin progress bar while earlier suggestions stay on screen.
          SizedBox(
            height: 2,
            child: _isLoading && _results.isNotEmpty
                ? const LinearProgressIndicator(minHeight: 2)
                : const Divider(height: 1),
          ),
          if (_service.useMockData)
            const _Notice(
              'Sample data mode: search only knows a few sample places. Build '
              'with USE_MOCK_DATA=false and a backend URL for real search.',
            ),
          if (_degraded && _results.isNotEmpty)
            const _Notice(
              'Location search is limited right now, so only a few known '
              'Bengaluru places are shown. Try again shortly for full results.',
            ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _results.isEmpty) {
      return const _SearchingIndicator();
    }

    final String? error = _errorMessage;
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: ErrorMessage(
          message: error,
          onRetry: () => _search(normalizeSearchQuery(_controller.text)),
        ),
      );
    }

    if (!_hasSearched) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: EmptyMessage(
          message: _tooShort
              ? 'Keep typing: enter at least '
                  '${LocationSearchService.minQueryLength} characters.'
              : 'Type a place name to search for your destination.',
          icon: Icons.travel_explore_outlined,
        ),
      );
    }

    if (_results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'No locations found',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const EmptyMessage(
              message: "Couldn't find that location. Try a different search.",
              icon: Icons.search_off,
            ),
            const SizedBox(height: 12),
            Text(
              'Try part of the name, another spelling, the area or city '
              '(e.g. "Indiranagar, Bengaluru"), a landmark, road or pincode.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.35),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      // Scrolling the list hides the keyboard so every result is reachable.
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: _results.length,
      separatorBuilder: (BuildContext context, int index) =>
          const Divider(height: 1, indent: 56),
      itemBuilder: (BuildContext context, int index) {
        final LocationModel place = _results[index];
        final bool noRiskData = place.crimeDataAvailable == false;
        return ListTile(
          leading: const Icon(
            Icons.place_outlined,
            color: AppColors.textSecondary,
          ),
          title: Text(
            place.name,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
          subtitle: place.address == null && !noRiskData
              ? null
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (place.address != null) Text(place.address!),
                    if (noRiskData)
                      const Text(
                        'No crime-risk estimate here',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                  ],
                ),
          onTap: () => Navigator.of(context).pop(place),
        );
      },
    );
  }
}

/// Spinner with its label, centred horizontally just below the search field.
///
/// Aligned to the top of the results area so it never drifts to the middle
/// or bottom of a tall (or keyboard-shortened) screen.
class _SearchingIndicator extends StatelessWidget {
  const _SearchingIndicator();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 32),
        child: Column(
          key: const ValueKey<String>('search-loading'),
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.6),
            ),
            const SizedBox(height: 12),
            Text('Searching…', style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}

/// One-line informational banner under the search field.
class _Notice extends StatelessWidget {
  const _Notice(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.primaryLight,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.info_outline, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}
