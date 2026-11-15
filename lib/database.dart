import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class FinDatabase {
  FinDatabase._();
  static final instance = FinDatabase._();
  Database? _db;
  Future<Database> get database async => _db ??= await _open();
  Future<Database> _open() async => openDatabase(p.join(await getDatabasesPath(),'finledger.db'),version:1,onCreate:(db,_)async{
    await db.execute('''CREATE TABLE transactions(id INTEGER PRIMARY KEY AUTOINCREMENT, amount REAL NOT NULL, type TEXT NOT NULL, category TEXT, merchant TEXT, description TEXT, date INTEGER NOT NULL, mode TEXT, account TEXT, fingerprint TEXT UNIQUE, source TEXT)''');
    await db.execute('''CREATE TABLE sms_queue(id INTEGER PRIMARY KEY AUTOINCREMENT, sender TEXT, body TEXT, received_at INTEGER)''');
  });
  Future<int> insert(Map<String,Object?> row) async {try{return await (await database).insert('transactions',row,conflictAlgorithm:ConflictAlgorithm.ignore);}catch(_){return 0;}}
  Future<List<Map<String,Object?>>> transactions(DateTime month) async {final start=DateTime(month.year,month.month).millisecondsSinceEpoch;final end=DateTime(month.year,month.month+1).millisecondsSinceEpoch;return (await database).query('transactions',where:'date >= ? AND date < ?',whereArgs:[start,end],orderBy:'date DESC');}
}
