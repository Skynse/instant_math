# Model Access Options

## Current Setup (No Authentication Required)

The app is now configured to use **SmolLM 135M**, which is:
- ✅ **Publicly accessible** - No HuggingFace token needed
- ✅ **Ultra-small** - Only 135MB download
- ✅ **Fast** - Runs efficiently on mobile devices
- ✅ **Good for math** - Can handle basic problem solving

## Alternative Models

### Option 1: SmolLM 135M (Current - Recommended)
```dart
static const String _modelUrl = 
    'https://huggingface.co/litert-community/SmolLM-135M-Instruct/resolve/main/SmolLM-135M-Instruct.task';
static const ModelType _modelType = ModelType.general;
```
- Size: ~135MB
- Speed: Very fast
- Quality: Good for basic math
- Auth: Not required

### Option 2: Qwen 2.5 0.5B (Better Quality)
```dart
static const String _modelUrl = 
    'https://huggingface.co/litert-community/Qwen2.5-0.5B-Instruct/resolve/main/Qwen2.5-0.5B-Instruct.task';
static const ModelType _modelType = ModelType.qwen;
```
- Size: ~500MB
- Speed: Fast
- Quality: Better reasoning
- Auth: Not required

### Option 3: Phi-4 Mini (Best Public Model)
```dart
static const String _modelUrl = 
    'https://huggingface.co/litert-community/Phi-4-mini-instruct/resolve/main/Phi-4-mini-instruct.task';
static const ModelType _modelType = ModelType.general;
```
- Size: ~3.9GB
- Speed: Moderate
- Quality: Excellent
- Auth: Not required

### Option 4: Gemma 3 270M (Requires Auth)
```dart
static const String _modelUrl = 
    'https://huggingface.co/litert-community/gemma-3-270m-it/resolve/main/gemma-3-270m-it.task';
static const ModelType _modelType = ModelType.gemmaIt;
```
- Size: ~300MB
- Speed: Fast
- Quality: Good
- Auth: **Required** - See below

## How to Get Access to Gemma Models

If you want to use Gemma models (better quality), follow these steps:

### Step 1: Create HuggingFace Account
1. Go to https://huggingface.co/join
2. Sign up with email or GitHub
3. Verify your email

### Step 2: Request Model Access
1. Visit https://huggingface.co/litert-community/gemma-3-270m-it
2. Click **"Request access"** button
3. Fill out the form (usually approved within hours)

### Step 3: Get Your Token
1. Go to https://huggingface.co/settings/tokens
2. Click **"New token"**
3. Name it "MathWizard" 
4. Select "Read" role
5. Copy the token

### Step 4: Add Token to App

#### Option A: Using config.json (Recommended)

1. Create `config.json` in project root:
```json
{
  "HUGGINGFACE_TOKEN": "hf_your_token_here"
}
```

2. Add to `.gitignore`:
```
config.json
```

3. Run app with config:
```bash
flutter run --dart-define-from-file=config.json
```

4. Update `main.dart`:
```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize with token
  const token = String.fromEnvironment('HUGGINGFACE_TOKEN');
  await FlutterGemma.initialize(
    huggingFaceToken: token.isNotEmpty ? token : null,
  );
  
  runApp(const MyApp());
}
```

#### Option B: Direct in Code (Not Recommended for Production)

```dart
await FlutterGemma.initialize(
  huggingFaceToken: 'hf_your_token_here', // ⚠️ Don't commit this!
);
```

## Model Comparison

| Model | Size | Speed | Quality | Auth Required |
|-------|------|-------|---------|---------------|
| SmolLM 135M | 135MB | ⭐⭐⭐⭐⭐ | ⭐⭐ | ❌ No |
| Qwen 2.5 0.5B | 500MB | ⭐⭐⭐⭐ | ⭐⭐⭐ | ❌ No |
| Gemma 3 270M | 300MB | ⭐⭐⭐⭐ | ⭐⭐⭐ | ✅ Yes |
| Phi-4 Mini | 3.9GB | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ❌ No |

## Recommendation

**For development/testing**: Use SmolLM 135M (current setup)
- Fast downloads
- No authentication
- Good enough for basic math

**For production**: 
1. Get HuggingFace token
2. Switch to Gemma 3 270M or Gemma 3 1B
3. Or use Phi-4 Mini if you have storage (3.9GB)

## Troubleshooting

### "Access to model is restricted"
- You're trying to use a gated model without authentication
- Switch to a public model (SmolLM, Qwen, Phi-4)
- Or get a HuggingFace token

### "Model download fails"
- Check internet connection
- Try a smaller model first
- Ensure sufficient storage space

### "Out of memory"
- Use a smaller model (SmolLM 135M)
- Close other apps
- Restart device

## Switching Models

To switch models, edit `lib/services/ai_service.dart`:

```dart
// Around line 21-26, change these values:
static const String _modelUrl = 'YOUR_MODEL_URL';
static const ModelType _modelType = ModelType.general; // or .gemmaIt, .qwen
static const String _modelName = 'model-name.task';
```

Then delete the old model and re-download:
1. Go to Settings screen
2. Delete current model
3. Restart app
4. Download new model
