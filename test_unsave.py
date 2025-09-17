import requests
import json

# Test the unsave endpoint
base_url = "http://localhost:5000"
test_user = "12345678-1234-1234-1234-123456789012"
test_word = "testword"
learning_language = "en"

print("Testing unsave functionality...")

# First save a word
save_data = {
    "word": test_word,
    "user_id": test_user,
    "learning_language": learning_language
}
save_response = requests.post(f"{base_url}/save", json=save_data)
print(f"1. Save word response: {save_response.status_code}")

# Check saved words
saved_response = requests.get(f"{base_url}/saved_words?user_id={test_user}")
saved_data = saved_response.json()
print(f"2. Words saved: {saved_data['count']}")

# Unsave the word
unsave_data = {
    "word": test_word,
    "user_id": test_user,
    "learning_language": learning_language
}
unsave_response = requests.post(f"{base_url}/unsave", json=unsave_data)
print(f"3. Unsave word response: {unsave_response.status_code}")
print(f"   Message: {unsave_response.json()}")

# Check saved words again
saved_response2 = requests.get(f"{base_url}/saved_words?user_id={test_user}")
saved_data2 = saved_response2.json()
print(f"4. Words saved after unsave: {saved_data2['count']}")

# Try to unsave a non-existent word
unsave_data2 = {
    "word": "nonexistentword",
    "user_id": test_user,
    "learning_language": learning_language
}
unsave_response2 = requests.post(f"{base_url}/unsave", json=unsave_data2)
print(f"5. Unsave non-existent word response: {unsave_response2.status_code}")
print(f"   Message: {unsave_response2.json()}")

print("\n✅ Unsave functionality test complete!")
