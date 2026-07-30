import 'package:flutter/material.dart';
import '../api/innertube_client.dart';

class AppProvider extends ChangeNotifier {
  final InnerTubeClient _client = InnerTubeClient();
  
  List<Video> _trendingVideos = [];
  List<Video> _searchResults = [];
  VideoDetails? _currentVideo;
  List<Video> _relatedVideos = [];
  List<Comment> _comments = [];
  
  bool _isLoading = false;
  String? _error;
  String _searchQuery = '';
  
  // Premium features settings
  bool _isDarkMode = true;
  bool _isAdBlockEnabled = true;
  bool _isSponsorBlockEnabled = true;
  bool _isBackgroundPlayEnabled = true;
  bool _isAutoPipEnabled = true;
  String _defaultQuality = '720p';
  double _defaultSpeed = 1.0;
  
  // Getters
  List<Video> get trendingVideos => _trendingVideos;
  List<Video> get searchResults => _searchResults;
  VideoDetails? get currentVideo => _currentVideo;
  List<Video> get relatedVideos => _relatedVideos;
  List<Comment> get comments => _comments;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get searchQuery => _searchQuery;
  
  bool get isDarkMode => _isDarkMode;
  bool get isAdBlockEnabled => _isAdBlockEnabled;
  bool get isSponsorBlockEnabled => _isSponsorBlockEnabled;
  bool get isBackgroundPlayEnabled => _isBackgroundPlayEnabled;
  bool get isAutoPipEnabled => _isAutoPipEnabled;
  String get defaultQuality => _defaultQuality;
  double get defaultSpeed => _defaultSpeed;

  // Load trending videos
  Future<void> loadTrending() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      _trendingVideos = await _client.getTrending();
    } catch (e) {
      _error = 'Failed to load trending videos';
      print('Error loading trending: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Search videos
  Future<void> searchVideos(String query) async {
    _searchQuery = query;
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      final result = await _client.search(query);
      _searchResults = result.videos;
    } catch (e) {
      _error = 'Failed to search videos';
      print('Error searching: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Load video details
  Future<void> loadVideoDetails(String videoId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      _currentVideo = await _client.getVideoDetails(videoId);
      _relatedVideos = await _client.getRelatedVideos(videoId);
      _comments = await _client.getComments(videoId);
    } catch (e) {
      _error = 'Failed to load video details';
      print('Error loading video details: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Clear search
  void clearSearch() {
    _searchQuery = '';
    _searchResults = [];
    notifyListeners();
  }

  // Toggle dark mode
  void toggleDarkMode() {
    _isDarkMode = !_isDarkMode;
    notifyListeners();
  }

  // Toggle ad block
  void toggleAdBlock() {
    _isAdBlockEnabled = !_isAdBlockEnabled;
    notifyListeners();
  }

  // Toggle SponsorBlock
  void toggleSponsorBlock() {
    _isSponsorBlockEnabled = !_isSponsorBlockEnabled;
    notifyListeners();
  }

  // Toggle background play
  void toggleBackgroundPlay() {
    _isBackgroundPlayEnabled = !_isBackgroundPlayEnabled;
    notifyListeners();
  }

  // Toggle auto PiP
  void toggleAutoPip() {
    _isAutoPipEnabled = !_isAutoPipEnabled;
    notifyListeners();
  }

  // Set default quality
  void setDefaultQuality(String quality) {
    _defaultQuality = quality;
    notifyListeners();
  }

  // Set default speed
  void setDefaultSpeed(double speed) {
    _defaultSpeed = speed;
    notifyListeners();
  }
}
