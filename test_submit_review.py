#!/usr/bin/env python3
import requests
import json

# Test the submit-review endpoint
url = "http://localhost:5000/v3/review/submit-review"
payload = {
    "user_id": "11111111-1111-1111-1111-111111111111",
    "word": "test",
    "learning_language": "en",
    "native_language": "zh",
    "response": True
}

print("Testing submit-review endpoint...")
print(f"POST {url}")
print(f"Payload: {json.dumps(payload, indent=2)}")
print()

try:
    response = requests.post(url, json=payload, timeout=10)
    print(f"Status Code: {response.status_code}")
    print(f"Response:")
    print(json.dumps(response.json(), indent=2))

    # Verify response structure
    data = response.json()
    if response.status_code == 200:
        print("\n✓ Status code is 200")
        if "new_badges" in data:
            print(f"✓ 'new_badges' field present: {data['new_badges']}")
            if data["new_badges"] is None:
                print("✓ 'new_badges' is None (as expected after badge removal)")
            else:
                print("✗ WARNING: 'new_badges' should be None but got:", data["new_badges"])
        else:
            print("✗ 'new_badges' field missing from response")

        if "practice_status" in data:
            print("✓ 'practice_status' field present")
        else:
            print("✗ 'practice_status' field missing")
    else:
        print(f"\n✗ Expected status code 200, got {response.status_code}")

except Exception as e:
    print(f"✗ Request failed: {e}")
