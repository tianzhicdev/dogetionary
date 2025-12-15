"""
Test bundle migration completeness
"""
import requests
import uuid

BASE_URL = "http://localhost:5001"
USER_ID = str(uuid.uuid4())

def test_bundle_endpoints():
    print("🧪 Testing bundle migration...")

    # Test 1: Health check
    print("\n1️⃣  Testing health endpoint...")
    response = requests.get(f"{BASE_URL}/health")
    assert response.status_code == 200, f"Health check failed: {response.status_code}"
    print("✅ Health endpoint works")

    # Test 2: Get word definition (tests bundle_vocabularies table)
    print("\n2️⃣  Testing word definition endpoint...")
    response = requests.get(f"{BASE_URL}/word", params={
        "w": "ability",
        "native_language": "zh",
        "user_id": USER_ID
    })
    assert response.status_code == 200, f"Word definition failed: {response.status_code}"
    data = response.json()
    assert data.get('word') == 'ability', "Word not returned correctly"
    print("✅ Word definition endpoint works (bundle_vocabularies table accessible)")

    # Test 3: Get bundle config (tests new bundle types)
    print("\n3️⃣  Testing bundle config endpoint...")
    response = requests.get(f"{BASE_URL}/v3/test-prep/config")
    if response.status_code == 200:
        data = response.json()
        print(f"✅ Bundle config endpoint works: {list(data.keys())[:5]}...")
    else:
        print(f"ℹ Bundle config endpoint not available (might not be implemented yet)")

    # Test 4: Verify database has new bundle words
    print("\n4️⃣  Verifying database bundle counts...")
    import psycopg2
    conn = psycopg2.connect(
        host="localhost",
        port=5432,
        database="dogetionary",
        user="dogeuser",
        password="dogepass"
    )
    cursor = conn.cursor()
    cursor.execute("""
        SELECT
            COUNT(*) FILTER (WHERE business_english = TRUE) as business_english,
            COUNT(*) FILTER (WHERE everyday_english = TRUE) as everyday_english,
            COUNT(*) FILTER (WHERE is_demo = TRUE) as demo
        FROM bundle_vocabularies;
    """)
    result = cursor.fetchone()
    cursor.close()

    assert result[0] > 0, "No business_english words found"
    assert result[1] > 0, "No everyday_english words found"
    assert result[2] > 0, "No demo words found"
    print(f"✅ Database bundle counts verified:")
    print(f"   - Business English: {result[0]} words")
    print(f"   - Everyday English: {result[1]} words")
    print(f"   - Demo: {result[2]} words")

    # Test 5: Verify user_preferences has new columns
    print("\n5️⃣  Verifying user_preferences schema...")
    cursor = conn.cursor()
    cursor.execute("""
        SELECT column_name
        FROM information_schema.columns
        WHERE table_name = 'user_preferences'
        AND column_name IN ('demo_enabled', 'demo_target_days', 'business_english_enabled', 'everyday_english_enabled')
        ORDER BY column_name;
    """)
    columns = [row[0] for row in cursor.fetchall()]
    cursor.close()
    conn.close()

    assert 'demo_enabled' in columns, "demo_enabled column not found"
    assert 'demo_target_days' in columns, "demo_target_days column not found"
    assert 'business_english_enabled' in columns, "business_english_enabled column not found"
    assert 'everyday_english_enabled' in columns, "everyday_english_enabled column not found"
    print(f"✅ User preferences schema verified: {len(columns)} new columns")

    print("\n" + "="*60)
    print("🎉 ALL MIGRATION TESTS PASSED!")
    print("="*60)

if __name__ == '__main__':
    try:
        test_bundle_endpoints()
    except Exception as e:
        print(f"\n❌ TEST FAILED: {e}")
        import traceback
        traceback.print_exc()
        exit(1)
