import 'dart:async';

import 'package:flutter/material.dart';

import '../models/location_model.dart';
import '../services/api_exception.dart';
import '../services/location_service.dart';
import '../utils/app_theme.dart';
import '../widgets/state_views.dart';

/// Destination search. Returns the chosen [LocationModel] to the caller.
class DestinationSearchScreen extends StatefulWidget {
  const DestinationSearchScreen({super.key, this.service});

  /// Injectable for tests; defaults to the real search service.
  final LocationSearchService? service;

  @override
  State<DestinationSearchScreen> createState() =>
      _DestinationSearchScreenState();
}

class _DestinationSearchScreenState extends State<DestinationSearchScreen> {
  late final LocationSearchService _service =
      widget.service ?? LocationSearchService();
  final TextEditingController _controller = TextEditingController();

  Timer? _debounce;
  List<LocationModel> _results = const <LocationModel>[];
  bool _isLoading = false;
  bool _hasSearched = false;
  String? _errorMessage;

  /// Guards against an earlier slow request overwriting a newer one.
  int _requestId = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    if (widget.service == null) _service.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final String query = value.trim();

    if (query.isEmpty) {
      setState(() {
        _results = const <LocationModel>[];
        _isLoading = false;
        _hasSearched = false;
        _errorMessage = null;
      });
      return;
    }

    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _search(query),
    );
  }

  Future<void> _search(String query) async {
    final int requestId = ++_requestId;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final List<LocationModel> results = await _service.search(query);
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _results = results;
        _isLoading = false;
        _hasSearched = true;
      });
    } on ApiException catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _isLoading = false;
        _hasSearched = true;
        _results = const <LocationModel>[];
        _errorMessage = error.message;
      });
    } catch (_) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _isLoading = false;
        _hasSearched = true;
        _results = const <LocationModel>[];
        _errorMessage = 'Could not search for that location.';
      });
    }
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
                if (value.trim().isNotEmpty) _search(value.trim());
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
          const Divider(height: 1),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const LoadingMessage(title: 'Searching...');
    }

    final String? error = _errorMessage;
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: ErrorMessage(
          message: error,
          onRetry: () => _search(_controller.text.trim()),
        ),
      );
    }

    if (!_hasSearched) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: EmptyMessage(
          message: 'Type a place name to search for your destination.',
          icon: Icons.travel_explore_outlined,
        ),
      );
    }

    if (_results.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: EmptyMessage(
          message: "Couldn't find that location. Try a different search.",
          icon: Icons.search_off,
        ),
      );
    }

    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (BuildContext context, int index) =>
          const Divider(height: 1, indent: 56),
      itemBuilder: (BuildContext context, int index) {
        final LocationModel place = _results[index];
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
          subtitle: place.address == null ? null : Text(place.address!),
          onTap: () => Navigator.of(context).pop(place),
        );
      },
    );
  }
}
