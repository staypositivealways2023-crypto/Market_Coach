"""Update Firestore security rules"""

import os
import sys

# Add parent directory to path
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from google.cloud import firestore
from google.oauth2 import service_account
from app.config import settings

def update_rules():
    """Update Firestore security rules"""

    # Read rules file
    rules_path = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(__file__))), 'firestore.rules')

    if not os.path.exists(rules_path):
        print(f"[ERROR] Rules file not found: {rules_path}")
        return

    with open(rules_path, 'r') as f:
        rules_content = f.read()

    print("Firestore security rules loaded from firestore.rules")
    print("\nTo deploy these rules, use Firebase CLI:")
    print("\n1. Install Firebase CLI if not already installed:")
    print("   npm install -g firebase-tools")
    print("\n2. Login to Firebase:")
    print("   firebase login")
    print("\n3. Initialize Firebase in your project:")
    print("   firebase init firestore")
    print("   (Select your project: marketcoach-db8f4)")
    print("\n4. Deploy the rules:")
    print("   firebase deploy --only firestore:rules")
    print("\nOR manually update in Firebase Console:")
    print("1. Go to: https://console.firebase.google.com/project/marketcoach-db8f4/firestore/rules")
    print("2. Copy the contents of firestore.rules")
    print("3. Paste and Publish")
    print("\n" + "="*60)
    print("Rules preview:")
    print("="*60)
    print(rules_content)

if __name__ == "__main__":
    update_rules()
