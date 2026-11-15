import 'package:flutter/services.dart';
import 'database.dart';

class SmsImporter {
  static const _channel = MethodChannel('com.finledger.app/sms');

  static final _amountPatterns = <RegExp>[
    RegExp(r'(?:debited|credited|withdrawn|deposited|spent|paid|payment of|purchase of)\D{0,24}(?:INR|Rs\.?|₹)\s*([0-9,]+(?:\.\d{1,2})?)', caseSensitive: false),
    RegExp(r'(?:INR|Rs\.?|₹)\s*([0-9,]+(?:\.\d{1,2})?)', caseSensitive: false),
  ];
  static final _accountPatterns = <RegExp>[
    RegExp(r'(?:A/c|account|ac(?:count)?)\s*(?:no\.?\s*)?(?:ending\s*(?:with)?\s*)?(?:xx|\*+|x+)?\s*([0-9]{3,6})\b', caseSensitive: false),
    RegExp(r'(?:XX|\*{2,}|X{2,})([0-9]{3,6})\b', caseSensitive: false),
    RegExp(r'(?:card|a/c)\s*(?:ending|no\.?)\s*(?:in)?\s*(?:xx|\*+)?([0-9]{3,6})\b', caseSensitive: false),
  ];
  static final _ref = RegExp(r'(?:UPI Ref(?:erence)?|Ref(?:erence)? No\.?|UTR|RRN)\s*[:#-]?\s*([A-Za-z0-9]{6,30})', caseSensitive: false);

  static Future<int> importInbox() async {
    final messages = await _channel.invokeListMethod<Map<dynamic, dynamic>>('importInbox') ?? [];
    return _saveMessages(messages);
  }

  static Future<int> importPending() async {
    final messages = await _channel.invokeListMethod<Map<dynamic, dynamic>>('getPendingSms') ?? [];
    return _saveMessages(messages);
  }

  static Future<int> _saveMessages(List<Map<dynamic, dynamic>> messages) async {
    var changed = 0;
    for (final raw in messages) {
      final body = (raw['body'] ?? '').toString();
      final sender = (raw['sender'] ?? '').toString();
      final date = (raw['date'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
      final parsed = _parse(body, sender, date);
      if (parsed != null) {
        changed += await FinDatabase.instance.upsertByFingerprint(parsed);
      }
    }
    return changed;
  }

  static Map<String, Object?>? _parse(String body, String sender, int date) {
    final lower = body.toLowerCase();
    final hasTransactionWord = RegExp(
      r'\b(debited|credited|withdrawn|deposited|spent|received|transferred|purchase|paid|payment|refund)\b',
    ).hasMatch(lower);
    if (!hasTransactionWord) return null;

    Match? amountMatch;
    for (final pattern in _amountPatterns) {
      amountMatch = pattern.firstMatch(body);
      if (amountMatch != null) break;
    }
    if (amountMatch == null) return null;
    final amount = double.tryParse(amountMatch.group(1)!.replaceAll(',', ''));
    if (amount == null || amount <= 0) return null;

    // A card-bill payment confirmation often says "payment received".
    // That means the card issuer received the payment, not that the user's
    // bank account received income. Keep it as a transfer to avoid inflating income
    // or double-counting the original card purchases as expenses.
    final isCardBillPayment = RegExp(
      r'(credit\s*card|card\s*(?:bill|payment)|card\s*account).{0,70}(payment|bill|paid|received|credited)|'
      r'(payment|bill|paid|received).{0,70}(credit\s*card|card\s*(?:bill|account))',
    ).hasMatch(lower);

    final isRefund = RegExp(r'\b(refund|reversed|reversal)\b').hasMatch(lower);
    final isDebit = RegExp(r'\b(debited|withdrawn|spent|purchase|paid)\b').hasMatch(lower);
    final isCredit = RegExp(r'\b(credited|deposited|received|refund)\b').hasMatch(lower);

    // Banks commonly send two SMS for one credit-card bill payment:
    // 1) the savings/current account is debited (keep this as TRANSFER);
    // 2) the credit-card account confirms payment received/credited (ignore it).
    // This prevents the card-side confirmation being counted a second time.
    final isCardSideReceipt = isCardBillPayment &&
        !isDebit &&
        RegExp(r'\b(received|credited|posted|thank you)\b').hasMatch(lower);
    if (isCardSideReceipt) return null;

    String type;
    String category;
    if (isCardBillPayment) {
      type = 'TRANSFER';
      category = 'Credit Card Payment';
    } else if (isRefund) {
      type = 'CREDIT';
      category = 'Refund';
    } else if (isDebit && !isCredit) {
      type = 'DEBIT';
      category = _category(body);
    } else if (isCredit && !isDebit) {
      type = 'CREDIT';
      category = _category(body);
    } else {
      return null;
    }

    final bank = _bankName('$body $sender');
    String? accountSuffix;
    for (final pattern in _accountPatterns) {
      accountSuffix = pattern.firstMatch(body)?.group(1);
      if (accountSuffix != null) break;
    }
    final account = [
      if (bank != null) bank else 'Bank account',
      if (accountSuffix != null) '••••$accountSuffix',
    ].join(' ');

    final ref = _ref.firstMatch(body)?.group(1);
    final merchant = _merchant(body);
    final mode = lower.contains('upi') ? 'UPI'
        : lower.contains('neft') ? 'NEFT'
        : lower.contains('imps') ? 'IMPS'
        : lower.contains('atm') ? 'ATM'
        : (lower.contains('pos') || lower.contains('card')) ? 'CARD'
        : 'BANK';

    final legacyDebit = RegExp(r'\b(debited|withdrawn|spent|paid|purchase)\b').hasMatch(lower);
    final fingerprint = ref != null
        ? 'sms-$ref'
        : 'sms-${sender.toLowerCase()}-${date ~/ 60000}-${amount.toStringAsFixed(2)}-${legacyDebit ? 'D' : 'C'}';

    return {
      'amount': amount,
      'type': type,
      'category': category,
      'merchant': merchant,
      'description': body.length > 240 ? body.substring(0, 240) : body,
      'date': date,
      'mode': mode,
      'account': account,
      'fingerprint': fingerprint,
      'source': 'SMS',
    };
  }

  static String? _bankName(String text) {
    final s = text.toLowerCase();
    const banks = <String, List<String>>{
      'HDFC Bank': ['hdfc', 'hdfcbk', 'hdfcbank'],
      'SBI': ['sbi', 'sbin', 'state bank of india'],
      'ICICI Bank': ['icici', 'icicib'],
      'Axis Bank': ['axis', 'axisbk'],
      'Kotak Mahindra Bank': ['kotak', 'kotakb'],
      'IDFC FIRST Bank': ['idfc', 'idfcbank'],
      'IndusInd Bank': ['indusind'],
      'Yes Bank': ['yesbank', 'yesb'],
      'Bank of Baroda': ['bob', 'bank of baroda'],
      'Canara Bank': ['canara'],
      'Union Bank': ['union bank'],
      'Punjab National Bank': ['pnb', 'punjab national'],
      'Federal Bank': ['federal'],
      'AU Small Finance Bank': ['aubank', 'au small finance'],
      'Paytm Payments Bank': ['paytm'],
    };
    for (final entry in banks.entries) {
      if (entry.value.any(s.contains)) return entry.key;
    }
    return null;
  }

  static String _merchant(String body) {
    final patterns = <RegExp>[
      RegExp(r'(?:to|at|towards|merchant[: ]+)\s*([A-Za-z0-9._@ -]{2,36})', caseSensitive: false),
      RegExp(r'(?:VPA)[: ]+([A-Za-z0-9._@-]{3,40})', caseSensitive: false),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(body);
      if (m != null) {
        return m.group(1)!.trim().replaceAll(RegExp(r'[\s.,;]+$'), '');
      }
    }
    return '';
  }

  static String _category(String text) {
    final s = text.toLowerCase();
    if (RegExp(r'swiggy|zomato|restaurant|food').hasMatch(s)) return 'Food';
    if (RegExp(r'grocery|bigbasket|blinkit|zepto').hasMatch(s)) return 'Groceries';
    if (RegExp(r'amazon|flipkart|myntra|shopping').hasMatch(s)) return 'Shopping';
    if (RegExp(r'uber|ola|irctc|flight|fuel|petrol').hasMatch(s)) return 'Travel';
    if (RegExp(r'electricity|water|bill|recharge').hasMatch(s)) return 'Bills';
    if (RegExp(r'salary|payroll').hasMatch(s)) return 'Salary';
    if (RegExp(r'transfer|imps|neft|rtgs').hasMatch(s)) return 'Transfer';
    return 'Other';
  }
}
