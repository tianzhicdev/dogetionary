# Cloudflare Cache Setup - Step by Step

## Step 1: Login to Cloudflare Dashboard

1. Go to https://dash.cloudflare.com
2. Select your domain: **kwafy.com**

## Step 2: Create Cache Rule

### Option A: Using Cache Rules (New Interface - Recommended)

1. Click on **Caching** in the left sidebar
2. Click on **Cache Rules** tab
3. Click **Create rule** button
4. Fill in the form:
   - **Rule name**: `Cache Video API`
   - **When incoming requests match...**:
     - Click "Edit expression"
     - Paste this: `(http.request.uri.path matches "^/api/v3/videos/.*")`
   - **Then...**:
     - **Eligible for cache**: Toggle to `On`
     - **Edge Cache TTL**: Select `Respect existing headers` (or set to `1 year`)
     - Click "Deploy"

### Option B: Using Page Rules (If Cache Rules not available)

1. Click on **Rules** in the left sidebar
2. Click on **Page Rules**
3. Click **Create Page Rule**
4. Fill in:
   - **URL pattern**: `*kwafy.com/api/v3/videos/*`
   - Click **Add a Setting**
   - Select **Cache Level** → Set to `Cache Everything`
   - Click **Add a Setting**
   - Select **Edge Cache TTL** → Set to `a year`
   - Click **Save and Deploy**

## Step 3: Verify the Rule is Active

1. In Cloudflare dashboard, go to the Cache Rules or Page Rules section
2. Verify the rule shows as **Active** or **Enabled**
3. Wait 1-2 minutes for the rule to propagate globally

## Step 4: Test Cache is Working

Use the test script we created to verify caching:

```bash
# Test from production
./scripts/measure_video_cache.sh 40 https://kwafy.com
```

You should see output like:
```
Test 1: CACHE MISS (First Request)
cf-cache-status: MISS
Time: ~1-2 seconds

Test 2: CACHE HIT (Second Request)
cf-cache-status: HIT
Time: ~0.1-0.3 seconds
Improvement: 80-90%
```

## What Each Cache Status Means

- **HIT**: Video served from Cloudflare edge (fast!) ✅
- **MISS**: First request, fetched from origin, now cached
- **BYPASS**: Not being cached - check your rule configuration ❌
- **DYNAMIC**: Cloudflare won't cache - need to fix rule ❌
- **EXPIRED**: Cache expired, revalidating

## Troubleshooting

If you see **BYPASS** or **DYNAMIC**:
1. Verify Cache Rule is enabled
2. Check URL pattern matches exactly
3. Make sure "Cache Everything" or "Eligible for cache: On" is set
4. Wait 2-3 minutes and test again
5. Try clearing Cloudflare cache: Caching → Configuration → Purge Everything

## Expected Performance

| Request | Time | Source |
|---------|------|--------|
| 1st (MISS) | 1-2s | Origin server |
| 2nd+ (HIT) | 0.1-0.3s | Cloudflare edge |
| Improvement | 80-90% faster | - |
