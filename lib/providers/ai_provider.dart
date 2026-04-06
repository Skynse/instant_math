import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/ai_service.dart';

/// Provider for the AI Service singleton.
final aiServiceProvider = Provider<AIService>((ref) {
  return AIService();
});

/// Minimal model state — kept for screens that still reference it.
class ModelState {
  final bool isLoading;
  final bool isLoaded;
  final bool isInstalled;
  final String? error;
  final String status;

  const ModelState({
    this.isLoading = false,
    this.isLoaded = true,
    this.isInstalled = true,
    this.error,
    this.status = 'Server-based — no local model needed',
  });

  ModelState copyWith({
    bool? isLoading,
    bool? isLoaded,
    bool? isInstalled,
    String? error,
    String? status,
  }) {
    return ModelState(
      isLoading: isLoading ?? this.isLoading,
      isLoaded: isLoaded ?? this.isLoaded,
      isInstalled: isInstalled ?? this.isInstalled,
      error: error ?? this.error,
      status: status ?? this.status,
    );
  }
}

class ModelNotifier extends StateNotifier<ModelState> {
  ModelNotifier() : super(const ModelState());

  void clearError() => state = state.copyWith(error: null);
}

final modelProvider = StateNotifierProvider<ModelNotifier, ModelState>((ref) {
  return ModelNotifier();
});
