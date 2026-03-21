/// Filter for cleaning model outputs and removing special tokens
class ModelOutputFilter {
  /// List of patterns to remove from model output
  static final List<RegExp> _patterns = [
    // Remove <unused> tokens
    RegExp(r'<unused\d+>'),
    // Remove <pad> tokens
    RegExp(r'<pad>'),
    // Remove <end_of_turn> tags (Gemma models)
    RegExp(r'<end_of_turn>'),
    // Remove <start_of_turn> tags
    RegExp(r'<start_of_turn>'),
    // Remove <bos> and <eos> tokens
    RegExp(r'<bos>'),
    RegExp(r'<eos>'),
    // Remove multiple spaces
    RegExp(r'\s+'),
  ];

  /// Clean model output by removing special tokens
  static String clean(String output) {
    String cleaned = output;
    
    // Apply all filters
    for (final pattern in _patterns) {
      cleaned = cleaned.replaceAll(pattern, ' ');
    }
    
    // Trim whitespace
    cleaned = cleaned.trim();
    
    // Remove leading/trailing newlines
    cleaned = cleaned.replaceAll(RegExp(r'^\n+|\n+$'), '');
    
    return cleaned;
  }

  /// Check if output contains only special tokens (garbage)
  static bool isGarbage(String output) {
    // Remove all special tokens
    String cleaned = output;
    for (final pattern in _patterns) {
      cleaned = cleaned.replaceAll(pattern, '');
    }
    cleaned = cleaned.trim();
    
    // If nothing meaningful remains, it's garbage
    return cleaned.isEmpty;
  }

  /// Extract meaningful content from potentially garbled output
  static String? extractContent(String output) {
    // First clean it
    String cleaned = clean(output);
    
    // If it's garbage, return null
    if (isGarbage(cleaned)) {
      return null;
    }
    
    return cleaned;
  }
}
