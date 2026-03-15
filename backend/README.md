# SIBNA Authentication System v2.5

## 🎯 Features

### ✅ SIM Auto-Detection
```
1. The app automatically reads the SIM card number
2. Sends it to the backend for verification
3. If matched → Fast registration without OTP
4. If not matched → Email OTP (6 digits)
```

### ✅ Email OTP (6 digits only)
```
┌──────────────────────────────────────────────┐
│           Email OTP - 6 Digits               │
├──────────────────────────────────────────────┤
│                                               │
│  Verification Code: 123456                   │
│  Valid for: 02 minutes                       │
│                                               │
└──────────────────────────────────────────────┘
```

### ✅ Automated Fallback
```
┌─────────────┐
│ Read SIM    │
└──────┬──────┘
       │
       ▼
┌─────────────┐    Match     ┌───────────┐
│   Compare   │──────────────▶│  SUCCESS  │
└──────┬──────┘              └───────────┘
       │ No Match
       ▼
┌─────────────────────┐
│   Fallback:         │
│ 1. Manual Entry     │
│ 2. Email OTP (6 num)│
└─────────────────────┘
```

---

## 🚀 Getting Started

```bash
# 1. Create Environment
python -m venv venv

# Windows
venv\Scripts\activate
# Mac/Linux
# source venv/bin/activate

# 2. Install Requirements
pip install -r requirements.txt

# 3. Run Server
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

---

## 📱 Endpoints

### SIM Verification
```
POST /auth/sim/detect
→ Instructions for SIM reading

POST /auth/sim/verify
→ Verification of SIM match
→ If matched: sim_verified = true
→ If not matched: fallback = email_otp
```

### Email OTP (6 Digits)
```
POST /auth/link-email
→ Send 6-digit code to email

POST /auth/verify-otp
→ Verify 6-digit code
```

### Registration & Login
```
POST /auth/register
POST /auth/challenge
POST /auth/verify-challenge
```

---

## 📋 Flutter Example

```dart
// 1. Read SIM number
import 'package:sim_card_info/sim_card_info.dart';

final SimCardInfo simCardInfo = SimCardInfo();
final simInfo = await simCardInfo.getSimInfo();
String? simPhone = simInfo.phoneNumber;

// 2. Verify
final response = await http.post(
  Uri.parse('https://api.com/auth/sim/verify'),
  body: jsonEncode({
    'sim_phone': simPhone,
    'entered_phone': userPhone,
    'country_code': 'SA',
    'device_id': deviceId,
  }),
);

final data = jsonDecode(response.body);

if (data['status'] == 'sim_verified') {
  // ✅ SIM matched - Fast registration
  registerUser(data['phone']);
} else {
  // ❌ Not matched - Use Email OTP
  // Send 6-digit code to email
  await sendEmailOtp(data['sim_info']['sim_phone'], email);
}
```

---

## ⚙️ Environment Variables

Create a `.env` file in the `backend` directory based on the `.env.example` file.

### How to generate your Keys:
1. **SECRET_KEY & JWT_SECRET:** Run this command in your terminal to generate cryptographically secure random strings:
   ```bash
   python -c "import secrets; print(secrets.token_hex(32))"
   ```
2. **SMTP_PASSWORD (Google):** 
   - Go to your Google Account -> **Security**.
   - Enable **2-Step Verification**.
   - Go to **App passwords**.
   - Create a new app password for "SIBNA Auth" and use the generated 16-character code here.

```bash
# Security
SECRET_KEY=paste_generated_key_here
JWT_SECRET=paste_generated_key_here

# Email SMTP
SMTP_HOST=smtp.gmail.com
SMTP_PORT=465
SMTP_USERNAME=your-app@gmail.com
SMTP_PASSWORD=your-google-app-password

# OTP Timing
OTP_EXPIRY=120
JWT_EXPIRY_DAYS=30
```

---

## 🌍 Supported Countries

39 countries including:
- 🇸🇦 Saudi Arabia, 🇪🇬 Egypt, 🇦🇪 UAE
- 🇰🇼 Kuwait, 🇶🇦 Qatar, 🇧🇭 Bahrain, 🇴🇲 Oman
- 🇯🇴 Jordan, 🇱🇧 Lebanon, 🇸🇾 Syria, 🇮🇶 Iraq
- 🇲🇦 Morocco, 🇩🇿 Algeria, 🇹🇳 Tunisia, 🇱🇾 Libya
- 🇺🇸 USA, 🇬🇧 UK, 🇩🇪 Germany, 🇫🇷 France
- And more...

