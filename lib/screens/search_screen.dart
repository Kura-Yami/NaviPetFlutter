import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../data/app_state.dart';
import '../data/app_config.dart';
import '../data/campus_place.dart';
import '../data/campus_search_controller.dart';
import '../data/campus_search_gateway.dart';
import '../data/course_class.dart';
import '../data/mapbox_config.dart';
import '../data/navigation_models.dart';
import '../data/search_history_store.dart';
import '../data/search_location_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/campus_search_result_tile.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    this.gateway,
    this.locationProvider,
    this.historyStore,
    this.debounce = const Duration(milliseconds: 275),
    this.onSelected,
  });

  final CampusSearchGateway? gateway;
  final SearchLocationProvider? locationProvider;
  final SearchHistoryStore? historyStore;
  final Duration debounce;
  final ValueChanged<NaviDestination>? onSelected;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late final CampusSearchGateway _gateway;
  late final SearchHistoryStore _historyStore;
  late final CampusSearchController _searchController;
  late final bool _ownsGateway;
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  List<NaviDestination> _recent = const [];

  static const _campusDestinations = [
    NaviDestination(
      name: 'University Student Union',
      address: 'Food, events, services & lounge',
      coordinate: NavigationCoordinate(latitude: 33.7812, longitude: -118.1128),
    ),
    NaviDestination(
      name: 'University Library',
      address: 'Study spaces, computers & research',
      coordinate: NavigationCoordinate(latitude: 33.7789, longitude: -118.1140),
    ),
    NaviDestination(
      name: 'Student Recreation Center',
      address: 'Fitness, recreation & wellness',
      coordinate: NavigationCoordinate(latitude: 33.7854, longitude: -118.1107),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _ownsGateway = widget.gateway == null;
    _gateway =
        widget.gateway ??
        HttpCampusSearchGateway(baseUrl: AppConfig.backendBaseUrl);
    _historyStore = widget.historyStore ?? SearchHistoryStore();
    _searchController = CampusSearchController(
      gateway: _gateway,
      location: widget.locationProvider ?? GeolocatorSearchLocationProvider(),
      debounce: widget.debounce,
    )..addListener(_onSearchStateChanged);
    _loadHistory();
  }

  void _onSearchStateChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadHistory() async {
    try {
      final recent = await _historyStore.load();
      if (mounted) setState(() => _recent = recent);
    } catch (_) {
      // A malformed old preference should never prevent destination search.
      await _historyStore.clear();
    }
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onSearchStateChanged)
      ..dispose();
    _controller.dispose();
    _focusNode.dispose();
    final gateway = _gateway;
    if (_ownsGateway && gateway is HttpCampusSearchGateway) {
      gateway.dispose();
    }
    super.dispose();
  }

  NavigationCoordinate _anchor() {
    final courses = context.read<AppState>().classes;
    if (courses.isEmpty) {
      return const NavigationCoordinate(
        latitude: csulbLat,
        longitude: csulbLng,
      );
    }
    return NavigationCoordinate(
      latitude:
          courses.map((course) => course.latitude).reduce((a, b) => a + b) /
          courses.length,
      longitude:
          courses.map((course) => course.longitude).reduce((a, b) => a + b) /
          courses.length,
    );
  }

  void _onQueryChanged(String value) {
    _searchController.queryChanged(value);
  }

  Future<void> _selectSuggestion(CampusPlace suggestion) async {
    final destination = await _searchController.select(suggestion);
    if (destination != null) await _finish(destination);
  }

  Future<void> _finish(NaviDestination destination) async {
    _recent = await _historyStore.add(destination);
    if (!mounted) return;
    final onSelected = widget.onSelected;
    if (onSelected != null) {
      onSelected(destination);
    } else {
      context.pop(destination);
    }
  }

  Future<void> _clearHistory() async {
    await _historyStore.clear();
    if (mounted) setState(() => _recent = const []);
  }

  @override
  Widget build(BuildContext context) {
    final hasQuery = _controller.text.trim().isNotEmpty;
    return Scaffold(
      backgroundColor: AppColors.screenBg,
      appBar: AppBar(
        toolbarHeight: 70,
        backgroundColor: Colors.white,
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back),
        ),
        titleSpacing: 0,
        title: Container(
          height: 46,
          margin: const EdgeInsets.only(right: 16),
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            onChanged: _onQueryChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Where to, explorer?',
              prefixIcon: const Icon(Icons.search, size: 21),
              suffixIcon: hasQuery
                  ? IconButton(
                      onPressed: () {
                        _controller.clear();
                        _onQueryChanged('');
                      },
                      icon: const Icon(Icons.close, size: 20),
                    )
                  : const Icon(Icons.mic_none, size: 20),
              contentPadding: EdgeInsets.zero,
              filled: true,
              fillColor: Colors.white,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: const BorderSide(
                  color: AppColors.amber,
                  width: 1.4,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: const BorderSide(color: AppColors.amber, width: 2),
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          if (_searchController.status == CampusSearchStatus.loading)
            const LinearProgressIndicator(
              minHeight: 2,
              color: AppColors.yellow,
            ),
          Expanded(child: hasQuery ? _results() : _discovery()),
        ],
      ),
    );
  }

  Widget _results() {
    switch (_searchController.status) {
      case CampusSearchStatus.initial:
      case CampusSearchStatus.typing:
        return const Center(child: Text('Type at least two characters.'));
      case CampusSearchStatus.loading:
        return const Center(child: Text('Searching campus…'));
      case CampusSearchStatus.noResults:
        return const Center(child: Text('No destinations found.'));
      case CampusSearchStatus.offline:
        return _stateMessage(
          'You’re offline. Check your connection and retry.',
        );
      case CampusSearchStatus.permissionRequired:
        return _stateMessage(
          'Location permission is required for nearby searches.',
        );
      case CampusSearchStatus.locationUnavailable:
        return _stateMessage(
          'Location is unavailable. Turn on Location Services and retry.',
        );
      case CampusSearchStatus.apiError:
        return _stateMessage('Campus search is unavailable. Please retry.');
      case CampusSearchStatus.results:
        break;
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _searchController.results.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
      itemBuilder: (_, index) {
        final suggestion = _searchController.results[index];
        return CampusSearchResultTile(
          place: suggestion,
          onTap: () => _selectSuggestion(suggestion),
        );
      },
    );
  }

  Widget _stateMessage(String message) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _searchController.retry,
            child: const Text('Retry'),
          ),
        ],
      ),
    ),
  );

  Widget _discovery() {
    final courses = context.watch<AppState>().classes;
    final anchor = _anchor();
    final popular = [..._campusDestinations]
      ..sort(
        (a, b) => _distance(
          anchor,
          a.coordinate,
        ).compareTo(_distance(anchor, b.coordinate)),
      );
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: [
        Row(
          children: [
            Image.asset(
              'assets/images/shark_side.png',
              width: 48,
              height: 48,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Find your way,',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.petInk,
                  ),
                ),
                Text(
                  'Your companion is ready to lead!',
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 22),
        _sectionHeader(
          'Recent Searches',
          _recent.isEmpty ? null : 'Clear All',
          _clearHistory,
        ),
        const SizedBox(height: 10),
        if (_recent.isEmpty) _emptyRecent() else ..._recent.map(_recentCard),
        const SizedBox(height: 22),
        _sectionHeader('Popular Locations', null, null),
        const SizedBox(height: 10),
        _popularCard(
          popular.first,
          _distance(anchor, popular.first.coordinate),
        ),
        const SizedBox(height: 8),
        _sectionHeader('Near Your Classes', null, null),
        const SizedBox(height: 10),
        if (courses.isEmpty)
          _addClassesHint()
        else
          SizedBox(
            height: 112,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: courses.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, index) => _classCard(courses[index]),
            ),
          ),
      ],
    );
  }

  Widget _sectionHeader(String title, String? action, VoidCallback? onTap) =>
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.petInk,
            ),
          ),
          if (action != null)
            TextButton(
              onPressed: onTap,
              child: Text(
                action,
                style: const TextStyle(
                  color: AppColors.accentDark,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      );

  Widget _emptyRecent() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: AppShadows.soft,
    ),
    child: const Text(
      'Your last 3 destinations will appear here.',
      style: TextStyle(color: AppColors.muted, fontSize: 12),
    ),
  );

  Widget _recentCard(NaviDestination item) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      elevation: 1,
      child: ListTile(
        onTap: () => _finish(item),
        leading: const CircleAvatar(
          backgroundColor: Color(0xFFF1F5F9),
          child: Icon(Icons.history, color: AppColors.petInk, size: 19),
        ),
        title: Text(item.name, style: const TextStyle(fontSize: 13)),
        subtitle: Text(
          item.address,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 10),
        ),
      ),
    ),
  );

  Widget _popularCard(NaviDestination item, double miles) => InkWell(
    onTap: () => _finish(item),
    borderRadius: BorderRadius.circular(14),
    child: Container(
      height: 148,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: const Color(0xFF00376E),
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(
            backgroundColor: AppColors.yellow,
            child: Icon(
              Icons.school_outlined,
              color: AppColors.petInk,
              size: 19,
            ),
          ),
          const Spacer(),
          Text(
            item.name,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            item.address,
            style: const TextStyle(color: Color(0xFFD9E6F4), fontSize: 11),
          ),
          const SizedBox(height: 8),
          Text(
            '⌖ ${miles.toStringAsFixed(1)} miles from your classes',
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
        ],
      ),
    ),
  );

  Widget _classCard(CourseClass course) => InkWell(
    onTap: () => _finish(course.destination),
    borderRadius: BorderRadius.circular(14),
    child: Container(
      width: 196,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 70,
            decoration: BoxDecoration(
              color: const Color(0xFFE9EAEC),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.account_balance_outlined,
              color: AppColors.petInk,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  course.locationLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  course.courseCode,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: AppColors.muted),
                ),
                const SizedBox(height: 5),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.accentSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Class location',
                    style: TextStyle(fontSize: 8, color: AppColors.amberInk),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _addClassesHint() => InkWell(
    onTap: () => context.push('/checklist'),
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: const Row(
        children: [
          Icon(Icons.add_circle_outline, color: AppColors.petInk),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Add your classes to see nearby destinations here.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    ),
  );

  double _distance(NavigationCoordinate a, NavigationCoordinate b) {
    const radiusMiles = 3958.8;
    final lat1 = a.latitude * pi / 180;
    final lat2 = b.latitude * pi / 180;
    final deltaLat = (b.latitude - a.latitude) * pi / 180;
    final deltaLng = (b.longitude - a.longitude) * pi / 180;
    final value =
        sin(deltaLat / 2) * sin(deltaLat / 2) +
        cos(lat1) * cos(lat2) * sin(deltaLng / 2) * sin(deltaLng / 2);
    return radiusMiles * 2 * atan2(sqrt(value), sqrt(1 - value));
  }
}
