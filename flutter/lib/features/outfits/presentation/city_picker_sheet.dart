import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../data/outfit_repository.dart';
import '../domain/outfit_weather.dart';
import '../../../core/widgets/hanger_loading_indicator.dart';

class CityPickerSheet extends StatefulWidget {
  const CityPickerSheet({required this.token, required this.repository, super.key});

  final String token;
  final OutfitRepository repository;

  @override
  State<CityPickerSheet> createState() => _CityPickerSheetState();
}

class _CityPickerSheetState extends State<CityPickerSheet> {
  final _search = TextEditingController();
  Timer? _debounce;
  CancelToken? _cancelToken;
  List<OutfitLocation> _results = const [];
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _cancelToken?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _cancelToken?.cancel();
    final query = value.trim();
    if (query.length < 2) {
      setState(() {
        _results = const [];
        _error = null;
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    _debounce = Timer(const Duration(milliseconds: 300), () => _searchCities(query));
  }

  Future<void> _searchCities(String query) async {
    final cancelToken = CancelToken();
    _cancelToken = cancelToken;
    try {
      final results = await widget.repository.searchLocations(
        token: widget.token,
        query: query,
        cancelToken: cancelToken,
      );
      if (!mounted || _search.text.trim() != query) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } on DioException catch (error) {
      if (CancelToken.isCancel(error) || !mounted) return;
      setState(() {
        _error = 'Could not search cities. Try again.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: 440,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Choose a city', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(
            controller: _search,
            autofocus: true,
            onChanged: _onChanged,
            decoration: InputDecoration(
              hintText: 'Mumbai, London, Tokyo...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(width: 24, height: 24, child: HangerLoadingIndicator(size: 24.0)),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 8),
          if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
          Expanded(
            child: _results.isEmpty
                ? const Center(child: Text('Search for the city where you will be.'))
                : ListView.separated(
                    itemCount: _results.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, index) {
                      final location = _results[index];
                      return ListTile(
                        leading: const Icon(Icons.location_city_outlined),
                        title: Text(location.name),
                        onTap: () => Navigator.of(context).pop(location),
                      );
                    },
                  ),
          ),
        ]),
      ),
    ),
  );
}
