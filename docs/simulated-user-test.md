# Simulated user test (Windows browser)

Use synthetic stories only. This test runs the existing Flutter flow in Edge and the API against an isolated local SQLite database at `backend/.simulated-test/finpilot.db`. The browser version tests the journal, clarification, review, and confirmation journey; it does not validate native iPhone behavior.

## Start

Open two PowerShell terminals from the repository root.

Terminal 1:

```powershell
cd backend
..\.venv\Scripts\python.exe scripts\run_simulated_test.py
```

Terminal 2:

```powershell
cd mobile
flutter run -d edge --web-port 8080 --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

Open `http://localhost:8080` if Edge does not open automatically. In the app, choose **Assistant** to enter a story. Home shows confirmed, non-voided spending by currency, category, and recent date. Its check time is when the app last fetched these records; no bank feed is connected. The browser's microphone support can differ from the iPhone's; start with typed stories and treat voice as an optional separate check.

## Try three short journeys

1. **Included price.** Select English. Enter: “I paid 80 CAD for dinner. The 33 CAD drink was included in that 80 CAD.” Expect one user expense of **80 CAD**, not 113. Review the event and its date before confirming.
2. **Another payer.** Select Chinese. Enter: “妈妈替我付了18加元买咖啡豆。我没说是否需要还她。” Expect a clarification about repayment and no confirmed expense yet. Answer truthfully within this fictional scenario; if you choose that you already repaid her, review the repayment amount and exact repayment date before including it.
3. **A purchase avoided.** Select French. Enter: “J'ai envisagé d'acheter des chaussures à 180 CAD, mais je ne les ai pas achetées.” Expect **0 CAD** spent. Open the event and choose the single **confirm no purchase** action; no payment fields or expense transaction should appear.

After a confirmed expense, return to Home and open **Transactions**. The page shows only recorded expenses, their dates and merchants, and separate totals for each currency. Unconfirmed drafts and avoided purchases should not appear there. Tap a record to correct a detail with a reason, review its change history, or remove it from spending if someone else paid. Check that Home and Transactions totals update. This local test database keeps its records across runs until you deliberately remove it. The startup script adds correction columns to older simulated SQLite databases without deleting their records.

When a draft contains pending events, choose **Quick review one by one** to check one event at a time. Swipe left to record an accurate expense or swipe right to exclude it; the visible buttons provide the same choices. Tap the date row to choose a date from the calendar. FinPilot never guesses an unclear amount or payment responsibility, so those items cannot be recorded until they are resolved in the full review. An avoided purchase can only be confirmed as not purchased. Closing quick review preserves decisions already saved.

After confirming a draft, FinPilot asks in the selected input language whether you have anything else to add. **Yes** returns to Assistant with an empty input field; **No** returns to Home and refreshes the spending overview.

## iPhone Safari preview from Windows

This is a web preview for typed stories, not a native iPhone build. Connect the iPhone and Windows computer to the same Wi-Fi. In PowerShell, start the API with a new isolated test database:

```powershell
cd backend
..\.venv\Scripts\python.exe scripts\run_simulated_test.py --database-name finpilot-v2.db
```

Build the web app using your computer's current LAN address, then run the Dart preview server on that address. It serves the web app and forwards API requests through the same port, while the Python API stays on `127.0.0.1:8000`. This avoids the Windows firewall rule that blocks inbound connections to Python on a Public Wi-Fi profile.

```powershell
$finpilotLanIp = '192.168.0.28' # Replace with your current Wi-Fi IPv4 address.
cd mobile
flutter build web --dart-define="API_BASE_URL=http://${finpilotLanIp}:8080"
cd ..
$flutterBin = Split-Path (Get-Command flutter).Source -Parent
& (Join-Path $flutterBin 'cache\dart-sdk\bin\dartvm.exe') scripts\serve_iphone_preview.dart $finpilotLanIp
```

Open `http://<LAN-IP>:8080` on iPhone Safari. Check `http://<LAN-IP>:8080/api/v1/health` if a request fails. Run the API in an environment that can reach the configured model service. Use fictional test stories only: the local preview has no user accounts or authentication. Browser voice recognition on plain HTTP may be unavailable on iPhone; typed stories are the supported test here.

## Record what you notice

For each journey, note whether the result was correct, where you hesitated, whether the wording felt reassuring, and what you expected the next button to do. A short note or screenshot of the unexpected screen is enough. Do not include personal financial details or an API key in feedback.

The avoided-purchase journey previously asked for **Payment responsibility** even though no payment happened. The review now recognizes an explicit saved decision with zero user expense and offers one confirmation action that excludes it from the ledger.

Stop both terminals with `Ctrl+C` when finished.
