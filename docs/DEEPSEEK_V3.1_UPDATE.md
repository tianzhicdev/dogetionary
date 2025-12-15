# DeepSeek Model Update: v3 → v3.1

## Summary

Updated all references from `deepseek/deepseek-chat` to `deepseek/deepseek-chat-v3.1` to fix the NotFoundError issue in production.

**Date**: December 14, 2025
**Issue**: NotFoundError appearing in Grafana metrics for definition.deepseek_v3
**Root Cause**: The model name `deepseek/deepseek-chat` is no longer available on OpenRouter
**Solution**: Update to the current model name `deepseek/deepseek-chat-v3.1`

---

## Changes Made

### 1. Configuration (`src/config/config.py`)

Updated all 6 occurrences in `FALLBACK_CHAINS`:
- `definition` chain (line 23)
- `question` chain (line 29)
- `user_profile` chain (line 35)
- `pronunciation` chain (line 41)
- `scene_description` chain (line 46)
- `general` chain (line 51)

**Before**:
```python
FALLBACK_CHAINS = {
    "definition": [
        "deepseek/deepseek-chat",        # OLD
        "qwen/qwen-2.5-7b-instruct",
        "mistralai/mistral-small",
        "openai/gpt-4o"
    ],
    # ... same for other chains
}
```

**After**:
```python
FALLBACK_CHAINS = {
    "definition": [
        "deepseek/deepseek-chat-v3.1",  # NEW
        "qwen/qwen-2.5-7b-instruct",
        "mistralai/mistral-small",
        "openai/gpt-4o"
    ],
    # ... same for other chains
}
```

### 2. LLM Utilities (`src/utils/llm.py`)

Updated 3 locations:

**a) Provider Mapping** (line 44):
```python
MODEL_PROVIDER_MAP = {
    # ...
    "deepseek/deepseek-chat-v3.1": "openrouter",  # Updated
    # ...
}
```

**b) Model Name Normalization** (line 70):
```python
model_map = {
    "deepseek/deepseek-chat-v3.1": "deepseek_v3",  # Updated
    # ...
}
```

**c) Documentation Comments**:
- Line 64: Docstring example
- Line 137: Comment in llm_completion_with_fallback
- Line 197: Comment in llm_completion

---

## Impact

### Metrics
- **Metric label remains unchanged**: `deepseek_v3`
- **Grafana dashboards**: No changes needed
- **Prometheus queries**: No changes needed

The normalized metric name stays as `deepseek_v3` to maintain consistency with existing dashboards and avoid breaking historical data.

### Expected Behavior After Deployment

**Before** (with old model):
```
Request for definition
    ↓
Try deepseek/deepseek-chat (OpenRouter)
    ↓
NotFoundError (404) - Model not available
    ↓
Metric: llm_errors_total{error_type="NotFoundError"} incremented
    ↓
Fallback to qwen/qwen-2.5-7b-instruct
```

**After** (with new model):
```
Request for definition
    ↓
Try deepseek/deepseek-chat-v3.1 (OpenRouter)
    ↓
Success! ✅
    ↓
Metric: llm_calls_total{status="success"} incremented
    ↓
No fallback needed
```

### Cost & Performance

- **No cost change**: DeepSeek V3.1 pricing is same as V3 (~$0.14/M tokens)
- **Performance**: Expected to be similar or better
- **Availability**: V3.1 is the current stable release

---

## Deployment

### Local Testing

1. **Rebuild the app**:
   ```bash
   ./start.sh
   ```

2. **Test a definition request**:
   ```bash
   curl -X POST http://localhost:5001/v4/word \
     -H "Content-Type: application/json" \
     -d '{"word": "hello", "language": "en", "user_id": "test-user"}'
   ```

3. **Check metrics**:
   ```bash
   # Should see successful calls, no NotFoundError
   curl -s http://localhost:5001/metrics | grep 'llm_calls_total.*deepseek'
   ```

### Production Deployment

1. **Pull latest code**:
   ```bash
   cd ~/dogetionary
   git pull origin main
   ```

2. **Rebuild and restart**:
   ```bash
   ./start.sh
   ```

3. **Monitor logs**:
   ```bash
   docker-compose logs -f app | grep -i "deepseek"
   ```

4. **Check Grafana** (after 5-10 minutes):
   - Navigate to LLM Metrics dashboard
   - Look for `definition.deepseek_v3` in "LLM Calls by Model" panel
   - Verify errors are decreasing
   - Confirm success rate is increasing

### Rollback Plan (if needed)

If issues occur with the new model:

```bash
# Revert config.py
git checkout HEAD~1 -- src/config/config.py src/utils/llm.py

# Rebuild
docker-compose build app --no-cache
docker-compose up -d app
```

---

## Verification

### Success Criteria

✅ No more NotFoundError in Grafana metrics for deepseek_v3
✅ Definition requests complete successfully with deepseek as first model
✅ Reduced fallback attempts to qwen/mistral/gpt-4o
✅ Lower latency (no need to retry multiple models)
✅ Lower cost (using cheapest model in chain)

### Monitoring Queries

**Check error rate**:
```logql
# Should be near zero after deployment
rate(llm_errors_total{model="deepseek_v3", error_type="NotFoundError"}[5m])
```

**Check success rate**:
```logql
# Should increase to ~95%+
rate(llm_calls_total{model="deepseek_v3", status="success"}[5m])
```

**Check fallback rate**:
```logql
# Should decrease significantly
sum(rate(llm_calls_total{model=~"qwen.*|mistral.*"}[5m]))
```

---

## References

- **OpenRouter Model Catalog**: https://openrouter.ai/models
- **DeepSeek Documentation**: https://platform.deepseek.com/docs
- **Related Issue**: NotFoundError investigation (Dec 14, 2025)
- **Grafana Dashboard**: LLM Metrics (http://localhost:3000/grafana)

---

## Files Changed

```
src/config/config.py          - Updated FALLBACK_CHAINS (6 occurrences)
src/utils/llm.py              - Updated MODEL_PROVIDER_MAP, normalization, docs (5 occurrences)
docs/DEEPSEEK_V3.1_UPDATE.md  - This file (documentation)
```

**Total**: 2 files modified, 11 occurrences updated

---

**Status**: ✅ Ready for deployment
