#!/bin/bash

# MongoDB Init Data Script for GodEyes Core
# This script initializes sample data for all collections

# Load environment variables from root .env file
if [ -f ../../.env ]; then
    source ../../.env
fi

set -e

# MongoDB connection settings
MONGO_HOST="${MONGO_HOST:-localhost}"
MONGO_PORT="${MONGO_PORT:-27017}"
MONGO_DB="${MONGO_DB:-godeyes}"
MONGO_USER="${MONGO_USER:-}"
MONGO_PASS="${MONGO_PASS:-}"

# Build connection string
if [ -n "$MONGO_USER" ] && [ -n "$MONGO_PASS" ]; then
    MONGO_URI="mongodb://${MONGO_USER}:${MONGO_PASS}@${MONGO_HOST}:${MONGO_PORT}/${MONGO_DB}?authSource=admin"
else
    MONGO_URI="mongodb://${MONGO_HOST}:${MONGO_PORT}/${MONGO_DB}"
fi

echo "==================================="
echo "GodEyes MongoDB Data Initialization"
echo "==================================="
echo "Database: $MONGO_DB"
echo "Host: $MONGO_HOST:$MONGO_PORT"
echo ""

# Function to insert data
insert_data() {
    local collection=$1
    local data=$2
    echo "Inserting data into '$collection' collection..."
    # Use a heredoc to run a small JS snippet in mongosh that inserts many documents
    # with { ordered: false } so duplicates do not stop the whole batch. Catch
    # duplicate-key errors (code 11000) and ignore them, rethrow other errors.
    docker exec -i godeyes-mongodb mongosh "$MONGO_URI" --quiet <<EOF
(function(){
  const docs = $data;
  try {
    db.getCollection("$collection").insertMany(docs, { ordered: false });
    print('Inserted documents into $collection (duplicates ignored)');
  } catch (e) {
    if (e && e.code === 11000) {
      print('Duplicate key errors ignored for $collection');
    } else {
      throw e;
    }
  }
})();
EOF
}

# 1. Initialize Devices Collection
echo ">>> Initializing Devices..."

# 2. Initialize Tenants Collection
echo ">>> Initializing Tenants..."
insert_data "tenants" '[
  {
    "tenant_id": "master",
    "name": "Godeyes Corp",
    "plan": "enterprise",
    "settings": {
      "notification_channels": "email,sms,webhook",
      "alert_threshold": "medium",
      "retention_days": 90,
      "max_devices": 100
    },
    "contact_info": {
      "email": "admin@godeyes.com",
      "phone": "+84396804066"
    },
    "active": true,
    "created_by": "system",
    "updated_by": "system",
    "created_at": new Date(),
    "updated_at": new Date()
  },
  {
    "tenant_id": "tenant-001",
    "name": "Security Corp",
    "plan": "enterprise",
    "settings": {
      "notification_channels": "email,sms,webhook",
      "alert_threshold": "medium",
      "retention_days": 90,
      "max_devices": 100
    },
    "contact_info": {
      "email": "admin@securitycorp.com",
      "phone": "+1-555-0123"
    },
    "active": true,
    "created_by": "system",
    "updated_by": "system",
    "created_at": new Date(),
    "updated_at": new Date()
  },
  {
    "tenant_id": "tenant-002",
    "name": "Smart City Solutions",
    "plan": "professional",
    "settings": {
      "notification_channels": "email,webhook",
      "alert_threshold": "high",
      "retention_days": 60,
      "max_devices": 50
    },
    "contact_info": {
      "email": "ops@smartcity.com",
      "phone": "+1-555-0456"
    },
    "active": true,
    "created_by": "system",
    "updated_by": "system",
    "created_at": new Date(),
    "updated_at": new Date()
  },
  {
    "tenant_id": "tenant-003",
    "name": "Fleet Management Inc",
    "plan": "standard",
    "settings": {
      "notification_channels": "email",
      "alert_threshold": "low",
      "retention_days": 30,
      "max_devices": 20
    },
    "contact_info": {
      "email": "support@fleetmgmt.com",
      "phone": "+1-555-0789"
    },
    "active": true,
    "created_by": "system",
    "updated_by": "system",
    "created_at": new Date(),
    "updated_at": new Date()
  }
]'

# 3. Initialize Sites Collection
echo ">>> Initializing Sites..."
insert_data "sites" '[
  {
    "site_id": "site-001",
    "name": "Headquarters",
    "address": "123 Main St",
    "city": "New York",
    "country": "USA",
    "timezone": "America/New_York",
    "geolocation": {
      "latitude": 40.7128,
      "longitude": -74.0060,
      "address": "123 Main St, New York, NY 10001",
      "city": "New York",
      "country": "USA"
    },
    "active": true,
    "created_by": "system",
    "updated_by": "system",
    "created_at": new Date(),
    "updated_at": new Date()
  },
  {
    "site_id": "site-002",
    "name": "West Coast Office",
    "address": "456 Tech Blvd",
    "city": "San Francisco",
    "country": "USA",
    "timezone": "America/Los_Angeles",
    "geolocation": {
      "latitude": 37.7749,
      "longitude": -122.4194,
      "address": "456 Tech Blvd, San Francisco, CA 94102",
      "city": "San Francisco",
      "country": "USA"
    },
    "active": true,
    "created_by": "system",
    "updated_by": "system",
    "created_at": new Date(),
    "updated_at": new Date()
  },
  {
    "site_id": "site-003",
    "name": "European Hub",
    "address": "789 Innovation Ave",
    "city": "London",
    "country": "UK",
    "timezone": "Europe/London",
    "geolocation": {
      "latitude": 51.5074,
      "longitude": -0.1278,
      "address": "789 Innovation Ave, London EC1A 1BB",
      "city": "London",
      "country": "UK"
    },
    "active": true,
    "created_by": "system",
    "updated_by": "system",
    "created_at": new Date(),
    "updated_at": new Date()
  },
  {
    "site_id": "site-004",
    "name": "Asia Pacific Center",
    "address": "321 Smart Street",
    "city": "Singapore",
    "country": "Singapore",
    "timezone": "Asia/Singapore",
    "geolocation": {
      "latitude": 1.3521,
      "longitude": 103.8198,
      "address": "321 Smart Street, Singapore 018956",
      "city": "Singapore",
      "country": "Singapore"
    },
    "active": true,
    "created_by": "system",
    "updated_by": "system",
    "created_at": new Date(),
    "updated_at": new Date()
  },
  {
    "site_id": "site-005",
    "name": "Hanoi Office",
    "address": "15 Hoang Quoc Viet",
    "city": "Hanoi",
    "country": "Vietnam",
    "timezone": "Asia/Ho_Chi_Minh",
    "geolocation": {
      "latitude": 21.0285,
      "longitude": 105.8542,
      "address": "15 Hoang Quoc Viet, Cau Giay, Hanoi",
      "city": "Hanoi",
      "country": "Vietnam"
    },
    "active": true,
    "created_by": "system",
    "updated_by": "system",
    "created_at": new Date(),
    "updated_at": new Date()
  }
]'


echo ""
echo "==================================="
echo "✓ Data initialization completed!"
echo "==================================="
echo ""
echo "Collection counts:"
docker exec -i godeyes-mongodb mongosh "$MONGO_URI" --quiet --eval "
  print('Devices: ' + db.devices.countDocuments());
  print('Tenants: ' + db.tenants.countDocuments());
  print('Sites: ' + db.sites.countDocuments());
"
