# Chinese, English, and French acceptance check

Use synthetic stories only. Select the matching input and reply language in the Flutter journal screen, or send the same `response_language` (`zh`, `en`, or `fr`) to `POST /api/v1/story-parser/parse`. Compare the financial result across languages, not the exact wording of the summary.

The parser endpoint does not write to the ledger. To verify the clarification flow, submit case 2 through `POST /api/v1/financial-drafts/from-journal` or the Flutter screen, then stop before confirming the draft.

| Case | 中文 | English | Français | Expected result in CAD |
| --- | --- | --- | --- | --- |
| 1. Included price | 我自己付了晚餐的80加元。饮料33加元已经包含在这80加元里。 | I paid 80 CAD for dinner. The 33 CAD drink was included in that 80 CAD. | J'ai payé 80 CAD pour le dîner. La boisson à 33 CAD était comprise dans ces 80 CAD. | User expense **80**, not 113. The drink is an included detail, not another expense. |
| 2. Initial payer is someone else | 妈妈替我付了18加元买咖啡豆。我没说是否需要还她。 | My mother paid 18 CAD for my coffee beans. I have not said whether I owe her. | Ma mère a payé 18 CAD pour mes grains de café. Je n'ai pas dit si je dois la rembourser. | Confirmed user expense **0** until responsibility is clarified. The draft asks whether repayment is due; it must not treat this as a gift or a completed repayment. |
| 3. Quantity, gift, and two emotions | 我很累但也很开心。朋友请我喝了8加元的奶茶，不用我还。我自己付12加元买了六盎司咖啡豆。 | I was tired but happy. My friend treated me to an 8 CAD milk tea; I owe nothing. I paid 12 CAD for six ounces of coffee beans. | J'étais fatigué mais heureux. Mon ami m'a offert un thé aux perles à 8 CAD ; je ne lui dois rien. J'ai payé 12 CAD pour six onces de grains de café. | User expense **12**. The friend's 8 is excluded. Six ounces is a quantity, not money. Both tired and happy are preserved. |
| 4. Purchase avoided | 我本来想买180加元的鞋，但最后没有买。 | I considered buying 180 CAD shoes but did not buy them. | J'ai envisagé d'acheter des chaussures à 180 CAD, mais je ne les ai pas achetées. | User expense **0**. The 180 is a decision not to buy, not a transaction. |

For every case, also check that the summary and any clarification question appear in the selected language, and that source quotes preserve the user's original words. On voice input, review the transcript before submitting, especially numbers, units, and who paid.

## Record results

| Case | Chinese | English | French | Notes / exact unexpected output |
| --- | --- | --- | --- | --- |
| 1 | Pass | Pass | Pass | User expense was 80 CAD in every language; the included 33 CAD drink was not counted twice. |
| 2 | Pass | Pass | Pass | Confirmed user expense stayed at 0 and every language asked whether the 18 CAD must be repaid. |
| 3 | Pass | Pass | Pass | User expense was 12 CAD, friend-paid total was 8 CAD, six ounces stayed a quantity, and both emotions were preserved. |
| 4 | Pass | Pass | Pass | User expense was 0 and the avoided purchase was recorded as a 180 CAD saved decision. |

On 2026-10-28, all 12 synthetic checks passed against the configured `gpt-5` API. The initial run exposed inconsistent `paid_by_others` totals for the English and Chinese versions of case 3. After enforcing `paid_by_other` for amounts in events explicitly covered by another person, all three versions of case 3 passed on rerun. No API key or real financial story was printed or stored in this document.

Run the live acceptance check from the backend directory:

```powershell
..\.venv\Scripts\python.exe scripts\test_multilingual_acceptance.py
```

Use `--case 3` or `--language zh` to limit a rerun.

Native iPhone testing requires a Mac with Xcode and an iPhone connected for development. The current Windows machine cannot build or install the iOS app. The iOS project already includes microphone, speech recognition, and local development network usage descriptions. Use the computer's LAN address for `API_BASE_URL` when testing against a local backend; `localhost` on an iPhone means the phone itself.

When a Mac is available, follow [Flutter's iOS device setup](https://docs.flutter.dev/platform-integration/ios/setup), choose a unique bundle ID and signing team in Xcode, and run the project from the Mac:

```bash
cd mobile
flutter pub get
flutter devices
flutter run -d <iphone-device-id> --dart-define=API_BASE_URL=http://<development-computer-LAN-IP>:8000
```

Connect the iPhone and backend computer to the same network. Use test stories only over the development HTTP connection. On the phone, allow microphone, speech recognition, and local network access when prompted. A production deployment needs HTTPS and user access controls before accepting real financial histories.
