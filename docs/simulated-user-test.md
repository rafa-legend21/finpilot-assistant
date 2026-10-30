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

Open `http://localhost:8080` if Edge does not open automatically. In the app, choose **Assistant** to enter a story. The home-screen budget figures are examples and should not be judged as real totals. The browser's microphone support can differ from the iPhone's; start with typed stories and treat voice as an optional separate check.

## Try three short journeys

1. **Included price.** Select English. Enter: “I paid 80 CAD for dinner. The 33 CAD drink was included in that 80 CAD.” Expect one user expense of **80 CAD**, not 113. Review the event and its date before confirming.
2. **Another payer.** Select Chinese. Enter: “妈妈替我付了18加元买咖啡豆。我没说是否需要还她。” Expect a clarification about repayment and no confirmed expense yet. Answer truthfully within this fictional scenario; if you choose that you already repaid her, review the repayment amount and exact repayment date before including it.
3. **A purchase avoided.** Select French. Enter: “J'ai envisagé d'acheter des chaussures à 180 CAD, mais je ne les ai pas achetées.” Expect **0 CAD** spent and no expense transaction for the shoes.

After a confirmed expense, `http://127.0.0.1:8000/api/v1/transactions` shows the recorded entry. `http://127.0.0.1:8000/api/v1/transactions/summary` shows its currency-separated total. Unconfirmed drafts should not appear there. This local test database keeps its records across runs until you deliberately remove it.

## Record what you notice

For each journey, note whether the result was correct, where you hesitated, whether the wording felt reassuring, and what you expected the next button to do. A short note or screenshot of the unexpected screen is enough. Do not include personal financial details or an API key in feedback.

Observed in the avoided-purchase journey: the review form still asks for **Payment responsibility** even though no payment happened. For now, select **Unknown**, keep **Your amount** at `0`, and choose **Exclude**. A future review form should make "not purchased" explicit and avoid asking who paid for an event that never happened.

Stop both terminals with `Ctrl+C` when finished.
