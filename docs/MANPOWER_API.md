# Manpower Time Tracking API Documentation

## 📋 Overview
The Manpower Time Tracking API provides a complete solution for integrating time tracking devices with workforce management. This API enables real-time employee attendance tracking with support for facial recognition and offline synchronization.

## 🔐 Authentication

### Base URL
```
http://100.109.133.12:3000/api/public/manpower
```

### Required Header
All API requests require an API key in the headers:
```
x-api-key: your_api_key_here
Content-Type: application/json
```

### Testing Credentials
- **Device ID**: `DEV-1757966710231-CJLZKWD`
- **Environment**: Development/Testing

## 📡 API Endpoints

### 1. Health Check
Verify device authentication and API connectivity.

**Endpoint:** `GET /health`

**Headers:**
```json
{
  "x-api-key": "your_api_key_here"
}
```

**Success Response (200):**
```json
{
  "status": "ok",
  "device": {
    "id": "DEV-123",
    "name": "Device Name",
    "location": "Main Office",
    "lastActivity": "2024-03-14T08:00:00Z"
  },
  "timestamp": "2024-03-14T08:00:00Z"
}
```

**Error Response (400):**
```json
{
  "message": "Invalid or inactive device",
  "error": "Bad Request",
  "statusCode": 400
}
```

### 2. Get Employees
Retrieve all employees for the device's company with pagination and photo filtering.

**Endpoint:** `GET /employees`

**Query Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| withPhotos | boolean | No | Filter employees with profile photos (default: false) |
| page | number | No | Page number for pagination (default: 1) |
| limit | number | No | Items per page (default: 50, max: 100) |

**Success Response (200):**
```json
{
  "employees": [
    {
      "id": "6c9c112b-ae6d-4a5c-846a-09e5bacac46f",
      "firstName": "John",
      "lastName": "Doe",
      "fullName": "John Doe",
      "employeeCode": "johndoe123",
      "department": "Main Branch",
      "position": "Regular Employee",
      "profilePhotoURL": "https://ante.sgp1.digitaloceanspaces.com/photo.jpeg",
      "hasProfilePhoto": true,
      "isActive": true
    }
  ],
  "total": 251,
  "page": 1,
  "limit": 50,
  "totalPages": 6
}
```

### 3. Clock In (Time-In)
Record employee time-in. Supports multiple sessions per day.

**Endpoint:** `POST /time-in`

**Request Body:**
```json
{
  "employeeId": "6c9c112b-ae6d-4a5c-846a-09e5bacac46f",
  "timestamp": "2024-03-14T08:00:00Z"  // Optional, uses server time if omitted
}
```

**Success Response (200):**
```json
{
  "timeRecordId": 123,
  "employeeId": "6c9c112b-ae6d-4a5c-846a-09e5bacac46f",
  "employeeName": "John Doe",
  "timeIn": "2024-03-14T08:00:00Z",
  "device": "Test Device",
  "message": "Time-in recorded successfully"
}
```

**Error Responses:**
- **404**: Employee not found or belongs to different company
- **400**: Invalid request data

### 4. Clock Out (Time-Out)
Record employee time-out. Enforces minimum 1-minute session duration.

**Endpoint:** `POST /time-out`

**Request Body:**
```json
{
  "timeRecordId": 123,
  "timestamp": "2024-03-14T17:00:00Z"  // Optional
}
```

**Success Response (200):**
```json
{
  "message": "Time-out recorded successfully. Computation queued.",
  "currentSession": {
    "timeRecordId": 770,
    "employeeId": "uuid-123-456",
    "employeeName": "John Doe",
    "timeIn": "2024-03-14T08:00:00Z",
    "timeOut": "2024-03-14T17:00:00Z",
    "duration": "9.00 hours"
  },
  "dailyRecords": [
    {
      "id": 770,
      "timeIn": "08:00 AM",
      "timeOut": "05:00 PM",
      "timeSpan": 9.00
    }
  ],
  "totalHoursToday": "9.00",
  "computationStatus": "queued",
  "queuePosition": 0,
  "queueJobId": "uuid-job-123"
}
```

**Error Responses:**
- **404**: Time record not found or not associated with device
- **400**: Minimum session duration not met (< 1 minute)

### 5. Employee Status
Check if an employee is currently clocked in or out.

**Endpoint:** `GET /employee-status`

**Query Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| employeeId | string | Yes | Employee UUID |

**Success Response (200) - Clocked In:**
```json
{
  "employeeId": "uuid-123-456",
  "employeeName": "John Doe",
  "status": "clocked_in",
  "since": "2024-03-14T08:00:00Z",
  "timeRecordId": 123
}
```

**Success Response (200) - Clocked Out:**
```json
{
  "employeeId": "uuid-123-456",
  "employeeName": "John Doe",
  "status": "clocked_out",
  "since": null,
  "timeRecordId": null
}
```

### 6. Daily Logs
Retrieve all time records created by this device for a specific date.

**Endpoint:** `GET /daily-logs`

**Query Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| date | string | Yes | Date in YYYY-MM-DD format |

**Success Response (200):**
```json
{
  "date": "2024-03-14",
  "totalRecords": 15,
  "records": [
    {
      "timeRecordId": 123,
      "employeeId": "uuid-123-456",
      "employeeCode": "EMP001",
      "employeeName": "John Doe",
      "timeIn": "2024-03-14T08:00:00Z",
      "timeOut": "2024-03-14T17:00:00Z",
      "hoursWorked": 9
    }
  ]
}
```

## 🔴 Error Codes

| Status Code | Description | Common Causes |
|------------|-------------|---------------|
| 200 | Success | Request processed successfully |
| 400 | Bad Request | Invalid parameters, missing API key, inactive device |
| 401 | Unauthorized | Invalid API key |
| 404 | Not Found | Employee/record not found, wrong company |
| 409 | Conflict | Duplicate entry (already clocked in) |
| 500 | Server Error | Internal server error |

## 💡 Implementation Guidelines

### Facial Recognition Integration
1. Use `GET /employees?withPhotos=true` to fetch employees with profile photos
2. Store profile photos locally for offline facial recognition
3. Use `profilePhotoURL` field to download employee photos for face encoding
4. Include confidence score when recording time-in/out

### Offline Support
1. Store employee data locally after sync
2. Queue time records when offline
3. Sync queued records when connection restored
4. Use exponential backoff for retry attempts

### Best Practices
1. Call `/health` endpoint periodically (every 5 minutes) to monitor connectivity
2. Cache employee list and refresh every hour
3. Handle multiple time-in/out sessions per day
4. Store `timeRecordId` from time-in response for corresponding time-out
5. All timestamps are in UTC - convert to local timezone for display

### Security Considerations
1. Store API key in secure storage
2. Never expose API key in logs or UI
3. Implement certificate pinning for production
4. Encrypt sensitive data locally
5. Clear data on device reset

## 📱 Device Setup Flow

1. **Initial Setup:**
   - Enter Device ID
   - Validate with `/health` endpoint
   - Store API key securely

2. **Employee Sync:**
   - Call `/employees?withPhotos=true`
   - Download profile photos
   - Generate face encodings
   - Store locally for offline use

3. **Daily Operation:**
   - Use facial recognition to identify employee
   - Call `/time-in` or `/time-out` based on status
   - Queue if offline, sync when online
   - Display feedback to user

## 🔄 Sync Strategy

### Initial Sync
- Fetch all employees with photos
- Download and process profile images
- Generate face embeddings
- Store in local database

### Periodic Sync (Every 15 minutes)
- Check for employee updates
- Update modified records only
- Remove inactive employees
- Update face encodings if photos changed

### Failed Sync Handling
- Retry with exponential backoff
- Max 3 retry attempts
- Store in failed queue after max attempts
- Alert admin if sync fails repeatedly

## 📊 Usage Examples

### Example: Complete Time Tracking Flow

```dart
// 1. Check device health
final healthCheck = await api.get('/health');

// 2. Get employee list
final employees = await api.get('/employees?withPhotos=true');

// 3. Check employee status
final status = await api.get('/employee-status?employeeId=$employeeId');

// 4. Clock in or out based on status
if (status.data['status'] == 'clocked_out') {
  // Clock in
  final result = await api.post('/time-in', {
    'employeeId': employeeId,
    'confidence': 0.95
  });
  final timeRecordId = result.data['timeRecordId'];
  // Store timeRecordId for later clock-out
} else {
  // Clock out
  await api.post('/time-out', {
    'timeRecordId': storedTimeRecordId,
    'confidence': 0.95
  });
}

// 5. Get daily logs
final logs = await api.get('/daily-logs?date=2024-03-14');
```

## 📝 Notes

- All endpoints require `x-api-key` header
- Device can only access employees from its assigned company
- Multiple time-in/out sessions per day are supported
- Background computation processes overtime and night differential
- Failed computations are automatically retried
- All timestamps should be in ISO 8601 format (UTC)