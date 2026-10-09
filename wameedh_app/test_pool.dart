import 'package:postgres/postgres.dart';

void main() async {
  final pool = Pool.withEndpoints(
    [Endpoint(
      host: 'ep-divine-tree-b5uupalq-pooler.c-7.us-east-2.aws.neon.tech',
      database: 'neondb',
      username: 'neondb_owner',
      password: 'npg_MARdTOHp06Yn',
      port: 5432,
    )],
    settings: PoolSettings(
      maxConnectionCount: 4,
    )
  );
  
  final res = await pool.execute("SELECT 1");
  print(res);
}
