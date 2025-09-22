# ANTE Facial Recognition Frontend

## Overview
Facial recognition module for the ANTE ERP system, providing biometric authentication and time tracking capabilities.

## Features
- Facial recognition for employee authentication
- Time-in/Time-out tracking
- Real-time face detection
- Employee registration and enrollment
- Attendance monitoring

## Technology Stack
- Vue.js 3
- TypeScript
- Quasar Framework
- WebRTC for camera access
- Face recognition API integration

## Prerequisites
- Node.js 18+
- Yarn package manager
- Camera/webcam access
- ANTE backend API running

## Installation
```bash
# Install dependencies
yarn install

# Start development server
yarn dev

# Build for production
yarn build
```

## Environment Variables
```env
VITE_API_URL=http://localhost:4000
VITE_SUPABASE_URL=your_supabase_url
VITE_SUPABASE_ANON_KEY=your_supabase_anon_key
VITE_FACE_API_KEY=your_face_api_key
```

## Development
This project follows the ANTE ERP standards:
- Material Design 3 (Flat design, no shadows)
- TypeScript strict mode
- Quasar component framework
- API integration patterns from `/documentation/standards/api-integration-guide.md`

## Project Structure
```
ante-facial-recognition/
├── src/
│   ├── components/     # Reusable components
│   ├── pages/          # Page components
│   ├── layouts/        # Layout components
│   ├── router/         # Vue Router configuration
│   ├── stores/         # Pinia stores
│   ├── services/       # API services
│   ├── composables/    # Vue composables
│   └── types/          # TypeScript types
├── public/             # Static assets
├── tests/              # Test files
└── package.json        # Project configuration
```

## Key Components
- **FaceCapture**: Camera interface for capturing facial data
- **FaceEnrollment**: Employee face registration
- **FaceVerification**: Authentication verification
- **AttendanceTracker**: Time tracking interface

## API Endpoints
- `POST /api/face/enroll` - Register employee face
- `POST /api/face/verify` - Verify employee identity
- `POST /api/attendance/clock-in` - Record time-in
- `POST /api/attendance/clock-out` - Record time-out

## Security Considerations
- Face data encryption in transit and at rest
- Secure token management
- Camera permissions handling
- Privacy compliance (GDPR, local regulations)

## Testing
```bash
# Run unit tests
yarn test:unit

# Run E2E tests
yarn test:e2e
```

## Deployment
Follow the standard ANTE deployment process:
1. Build the application: `yarn build`
2. Deploy using PM2: `pm2 start ecosystem.config.js`
3. Configure NGINX proxy

## License
Proprietary - GEER Solutions

## Support
For issues or questions, contact the ANTE development team.