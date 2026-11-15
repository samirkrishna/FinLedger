import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'database.dart';
import 'sms_importer.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FinDatabase.instance.database;
  runApp(const FinLedgerApp());
}

class FinLedgerApp extends StatelessWidget {
  const FinLedgerApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'FinLedger', debugShowCheckedModeBanner: false,
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF176B55), brightness: Brightness.light), useMaterial3: true, scaffoldBackgroundColor: const Color(0xFFF6F8F7)),
    home: const HomeScreen(),
  );
}

class HomeScreen extends StatefulWidget { const HomeScreen({super.key}); @override State<HomeScreen> createState() => _HomeScreenState(); }
class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  List<Map<String, Object?>> rows = [];
  int tab = 0;
  bool importing = false;
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  final money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
  @override void initState() { super.initState(); WidgetsBinding.instance.addObserver(this); _load(); }
  @override void dispose() { WidgetsBinding.instance.removeObserver(this); super.dispose(); }
  @override void didChangeAppLifecycleState(AppLifecycleState state) { if (state == AppLifecycleState.resumed) _load(); }
  Future<void> _load() async { try { await SmsImporter.importPending(); } catch (_) {} final data = await FinDatabase.instance.transactions(month); if (mounted) setState(() => rows = data); }
  double get credits => rows.where((e) => e['type'] == 'CREDIT').fold(0.0, (s,e) => s + (e['amount'] as num).toDouble());
  double get debits => rows.where((e) => e['type'] == 'DEBIT').fold(0.0, (s,e) => s + (e['amount'] as num).toDouble());
  Future<void> _import() async {
    setState(() => importing = true);
    try {
      final sms = await Permission.sms.request();
      if (!sms.isGranted) { _message('SMS permission is required for automatic bank transaction importing.'); return; }
      final count = await SmsImporter.importInbox();
      await _load();
      _message(count == 0 ? 'No new bank transactions found.' : 'Imported $count transaction(s).');
    } catch (e) { _message('Import could not be completed: $e'); }
    finally { if (mounted) setState(() => importing = false); }
  }
  void _message(String value) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value))); }
  Future<void> _add() async { final changed = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const AddTransactionScreen())); if (changed == true) _load(); }
  @override Widget build(BuildContext context) {
    final title = ['Overview', 'Ledger', 'Reports', 'Settings'][tab];
    return Scaffold(appBar: AppBar(title: Text('FinLedger · $title', style: const TextStyle(fontWeight: FontWeight.w700)), actions: [if(tab < 2) IconButton(onPressed: importing ? null : _import, tooltip: 'Import bank SMS', icon: importing ? const SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2)) : const Icon(Icons.sync))]),
      body: tab == 3 ? _settings() : tab == 2 ? _reports() : tab == 1 ? _ledger() : _dashboard(),
      floatingActionButton: tab < 2 ? FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.add), label: const Text('Add transaction')) : null,
      bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: (v)=>setState(()=>tab=v), destinations: const [NavigationDestination(icon:Icon(Icons.space_dashboard_outlined),selectedIcon:Icon(Icons.space_dashboard),label:'Home'),NavigationDestination(icon:Icon(Icons.receipt_long_outlined),selectedIcon:Icon(Icons.receipt_long),label:'Ledger'),NavigationDestination(icon:Icon(Icons.bar_chart),label:'Reports'),NavigationDestination(icon:Icon(Icons.settings_outlined),label:'Settings')]),
    );
  }
  Widget _monthPicker() => Row(children:[IconButton(onPressed:()=>setState(()=>month=DateTime(month.year,month.month-1)),icon:const Icon(Icons.chevron_left)),Expanded(child:Text(DateFormat('MMMM yyyy').format(month),textAlign:TextAlign.center,style:const TextStyle(fontWeight:FontWeight.w700,fontSize:16))),IconButton(onPressed:()=>setState(()=>month=DateTime(month.year,month.month+1)),icon:const Icon(Icons.chevron_right))]);
  Widget _dashboard() => RefreshIndicator(onRefresh:_load,child:ListView(padding:const EdgeInsets.fromLTRB(16,8,16,100),children:[_monthPicker(),_summaryCard(),const SizedBox(height:18),Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[const Text('Recent transactions',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),TextButton(onPressed:()=>setState(()=>tab=1),child:const Text('View all'))]),if(rows.isEmpty)_empty() else ...rows.take(6).map(_transactionTile)]));
  Widget _summaryCard()=>Container(padding:const EdgeInsets.all(20),decoration:BoxDecoration(color:const Color(0xFF176B55),borderRadius:BorderRadius.circular(22)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('NET CASH FLOW',style:TextStyle(color:Colors.white.withOpacity(.8),fontSize:11,letterSpacing:1.2)),const SizedBox(height:8),Text(money.format(credits-debits),style:const TextStyle(color:Colors.white,fontSize:30,fontWeight:FontWeight.bold)),const SizedBox(height:20),Row(children:[Expanded(child:_metric('Income',credits,Icons.south_west)),Expanded(child:_metric('Expenses',debits,Icons.north_east))]) ]));
  Widget _metric(String label,double amount,IconData icon)=>Row(children:[Icon(icon,color:Colors.white70,size:18),const SizedBox(width:7),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(label,style:const TextStyle(color:Colors.white70,fontSize:12)),Text(money.format(amount),style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w600))]))]);
  Widget _ledger()=>ListView(padding:const EdgeInsets.fromLTRB(16,8,16,100),children:[_monthPicker(),if(rows.isEmpty)_empty() else ...rows.map(_transactionTile)]);
  Widget _reports()=>ListView(padding:const EdgeInsets.all(16),children:[_monthPicker(),_summaryCard(),const SizedBox(height:18),const Text('Spending by category',style:TextStyle(fontWeight:FontWeight.bold,fontSize:18)),const SizedBox(height:10),..._categoryTotals().entries.map((e)=>Card(child:ListTile(title:Text(e.key),trailing:Text(money.format(e.value),style:const TextStyle(fontWeight:FontWeight.w700))))) ]);
  Map<String,double> _categoryTotals(){final m=<String,double>{};for(final r in rows.where((e)=>e['type']=='DEBIT')){final k=(r['category']??'Other').toString();m[k]=(m[k]??0)+(r['amount'] as num).toDouble();}return m;}
  Widget _settings()=>ListView(padding:const EdgeInsets.all(16),children:[const Text('On-device privacy',style:TextStyle(fontSize:19,fontWeight:FontWeight.bold)),const SizedBox(height:8),const Card(child:ListTile(leading:Icon(Icons.phonelink_lock),title:Text('Local-only storage'),subtitle:Text('Transactions are stored in this phone’s SQLite database. FinLedger has no backend or account login.'))),Card(child:ListTile(leading:const Icon(Icons.sms_outlined),title:const Text('Import bank SMS'),subtitle:const Text('Grant SMS permission and scan your inbox for bank transaction messages.'),onTap:_import)),const Card(child:ListTile(leading:Icon(Icons.info_outline),title:Text('Important'),subtitle:Text('SMS parsing depends on the bank message format. Review imported entries and correct any mistakes. OTPs and unrelated messages are not imported.')))]);
  Widget _empty()=>const Padding(padding:EdgeInsets.symmetric(vertical:50),child:Column(children:[Icon(Icons.receipt_long_outlined,size:48,color:Colors.grey),SizedBox(height:12),Text('No transactions for this month',style:TextStyle(color:Colors.grey)),Text('Import bank SMS or add a transaction manually.',style:TextStyle(color:Colors.grey,fontSize:12))]));
  Widget _transactionTile(Map<String,Object?> r)=>Card(margin:const EdgeInsets.only(bottom:8),child:ListTile(leading:CircleAvatar(backgroundColor:(r['type']=='CREDIT'?Colors.green:Colors.orange).withOpacity(.12),child:Icon(r['type']=='CREDIT'?Icons.south_west:Icons.north_east,color:r['type']=='CREDIT'?Colors.green:Colors.deepOrange)),title:Text((r['merchant']??r['description']??'Transaction').toString(),maxLines:1,overflow:TextOverflow.ellipsis),subtitle:Text('${r['category']??'Other'} · ${DateFormat('dd MMM').format(DateTime.fromMillisecondsSinceEpoch(r['date'] as int))}'),trailing:Text('${r['type']=='CREDIT'?'+':'−'}${money.format((r['amount'] as num).toDouble())}',style:TextStyle(fontWeight:FontWeight.w700,color:r['type']=='CREDIT'?Colors.green:Colors.black87))));
}

class AddTransactionScreen extends StatefulWidget { const AddTransactionScreen({super.key}); @override State<AddTransactionScreen> createState()=>_AddTransactionScreenState(); }
class _AddTransactionScreenState extends State<AddTransactionScreen>{final form=GlobalKey<FormState>();final amount=TextEditingController();final merchant=TextEditingController();final desc=TextEditingController();String type='DEBIT',category='Other';DateTime date=DateTime.now();final categories=['Food','Groceries','Shopping','Travel','Fuel','Bills','Rent','Salary','Transfer','Investment','Other'];
 @override void dispose(){amount.dispose();merchant.dispose();desc.dispose();super.dispose();}
 Future<void> save()async{if(!form.currentState!.validate())return;await FinDatabase.instance.insert({'amount':double.parse(amount.text),'type':type,'category':category,'merchant':merchant.text.trim(),'description':desc.text.trim(),'date':date.millisecondsSinceEpoch,'mode':'MANUAL','account':'','fingerprint':'manual-${DateTime.now().microsecondsSinceEpoch}','source':'MANUAL'});if(mounted)Navigator.pop(context,true);}
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Add transaction')),body:Form(key:form,child:ListView(padding:const EdgeInsets.all(18),children:[SegmentedButton<String>(segments:const[ButtonSegment(value:'DEBIT',label:Text('Expense'),icon:Icon(Icons.north_east)),ButtonSegment(value:'CREDIT',label:Text('Income'),icon:Icon(Icons.south_west))],selected:{type},onSelectionChanged:(s)=>setState(()=>type=s.first)),const SizedBox(height:18),TextFormField(controller:amount,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Amount (₹)',border:OutlineInputBorder()),validator:(v)=>double.tryParse(v??'')==null||double.parse(v!)<=0?'Enter a valid amount':null),const SizedBox(height:14),TextFormField(controller:merchant,decoration:const InputDecoration(labelText:'Merchant / source',border:OutlineInputBorder())),const SizedBox(height:14),DropdownButtonFormField<String>(value:category,decoration:const InputDecoration(labelText:'Category',border:OutlineInputBorder()),items:categories.map((c)=>DropdownMenuItem(value:c,child:Text(c))).toList(),onChanged:(v)=>setState(()=>category=v??'Other')),const SizedBox(height:14),TextFormField(controller:desc,decoration:const InputDecoration(labelText:'Notes (optional)',border:OutlineInputBorder())),const SizedBox(height:24),FilledButton(onPressed:save,child:const Padding(padding:EdgeInsets.all(12),child:Text('Save transaction')))])));
}
