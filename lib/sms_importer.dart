import 'package:flutter/services.dart';
import 'database.dart';

class SmsImporter {
  static const _channel=MethodChannel('com.finledger.app/sms');
  static final _amount=RegExp(r'(?:INR|Rs\.?|₹)\s*([0-9,]+(?:\.\d{1,2})?)',caseSensitive:false);
  static final _account=RegExp(r'(?:A/c|account|ac)\s*(?:no\.?\s*)?(?:xx|\*+)?([0-9]{3,6})',caseSensitive:false);
  static final _upi=RegExp(r'(?:to| at |VPA[: ]+)\s*([A-Za-z0-9._@-]{3,40})',caseSensitive:false);
  static final _ref=RegExp(r'(?:UPI Ref(?:erence)?|Ref(?:erence)? No\.?|UTR)\s*[:#-]?\s*([A-Za-z0-9]{6,30})',caseSensitive:false);
  static Future<int> importInbox() async {
    final messages=await _channel.invokeListMethod<Map<dynamic,dynamic>>('importInbox')??[];
    return _saveMessages(messages);
  }
  static Future<int> importPending() async {
    final messages=await _channel.invokeListMethod<Map<dynamic,dynamic>>('getPendingSms')??[];
    return _saveMessages(messages);
  }
  static Future<int> _saveMessages(List<Map<dynamic,dynamic>> messages) async {
    var added=0;
    for(final raw in messages){final body=(raw['body']??'').toString();final sender=(raw['sender']??'').toString();final date=(raw['date'] as num?)?.toInt()??DateTime.now().millisecondsSinceEpoch;final parsed=_parse(body,sender,date);if(parsed!=null){final n=await FinDatabase.instance.insert(parsed);if(n>0)added++;}}
    return added;
  }
  static Map<String,Object?>? _parse(String body,String sender,int date){
    final lower=body.toLowerCase();
    final bankLike=RegExp(r'\b(debited|credited|withdrawn|deposited|spent|received|transferred|purchase|paid)\b').hasMatch(lower);
    final amountMatch=_amount.firstMatch(body);
    if(!bankLike||amountMatch==null)return null;
    final debit=RegExp(r'\b(debited|withdrawn|spent|paid|purchase)\b').hasMatch(lower);
    final credit=RegExp(r'\b(credited|deposited|received)\b').hasMatch(lower);
    if(debit==credit)return null;
    final amount=double.tryParse(amountMatch.group(1)!.replaceAll(',',''));
    if(amount==null||amount<=0)return null;
    final acc=_account.firstMatch(body)?.group(1)??'';
    final ref=_ref.firstMatch(body)?.group(1);
    final merchant=_upi.firstMatch(body)?.group(1)??'';
    final category=_category('$body $merchant');
    final fingerprint=ref!=null?'sms-$ref':'sms-${sender.toLowerCase()}-${date ~/ 60000}-${amount.toStringAsFixed(2)}-${debit?'D':'C'}';
    return {'amount':amount,'type':debit?'DEBIT':'CREDIT','category':category,'merchant':merchant,'description':body.length>180?body.substring(0,180):body,'date':date,'mode':lower.contains('upi')?'UPI':lower.contains('neft')?'NEFT':lower.contains('imps')?'IMPS':lower.contains('atm')?'ATM':lower.contains('pos')?'CARD':'BANK','account':acc,'fingerprint':fingerprint,'source':'SMS'};
  }
  static String _category(String text){final s=text.toLowerCase();if(RegExp(r'swiggy|zomato|restaurant|food').hasMatch(s))return 'Food';if(RegExp(r'grocery|bigbasket|blinkit|zepto').hasMatch(s))return 'Groceries';if(RegExp(r'amazon|flipkart|myntra|shopping').hasMatch(s))return 'Shopping';if(RegExp(r'uber|ola|irctc|flight|fuel|petrol').hasMatch(s))return 'Travel';if(RegExp(r'electricity|water|bill|recharge').hasMatch(s))return 'Bills';if(RegExp(r'salary|payroll').hasMatch(s))return 'Salary';return 'Other';}
}
