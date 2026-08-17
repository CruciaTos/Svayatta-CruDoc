# doctor_management_app

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## AI Voice Receptionist

An AI-powered phone receptionist that answers incoming calls, books appointments into CruDoc, or transfers callers to a human receptionist.

- **Location**: [`voice-receptionist/`](./voice-receptionist/)
- **Tech**: Pipecat · Twilio · Sarvam AI · Google Gemini
- **Setup & deployment**: See [`voice-receptionist/README.md`](./voice-receptionist/README.md)

The voice receptionist is a standalone Python service that communicates with CruDoc's backend via a Cloud Function endpoint (`functions/src/appointments.ts`). Appointments booked by the AI appear in the CruDoc app in real time.

## WhatsApp Appointment Notification System

An automated WhatsApp notification engine that sends instant appointment confirmation messages to patients whenever a doctor, receptionist, or the AI Voice Receptionist books an appointment.

- **Guide & Documentation**: See [`WHATSAPP_INTEGRATION_GUIDE.md`](./WHATSAPP_INTEGRATION_GUIDE.md)
- **Features**: Meta WhatsApp Cloud API · 1-Click WhatsApp Companion · Real-time Delivery Status Tracking · Zero Medical Data Leakage · E.164 Normalization · Local SQLite & Cloud Audit Logs.
