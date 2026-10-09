import 'package:postgres/postgres.dart';

void main() async {
  print("Connecting to Neon...");
  final conn = await Connection.open(
    Endpoint(
      host: 'ep-divine-tree-b5uupalq-pooler.c-7.us-east-2.aws.neon.tech',
      database: 'neondb',
      username: 'neondb_owner',
      password: 'npg_MARdTOHp06Yn',
      port: 5432,
    ),
    settings: ConnectionSettings(sslMode: SslMode.require),
  );
  
  print("Connected! Fetching inventory...");
  final result = await conn.execute("SELECT id, name, quantity, category, date FROM inventory");
  for (final row in result) {
    print("Item: ${row[1]} (Qty: ${row[2]})");
  }
  
  await conn.close();
}
