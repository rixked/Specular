import 'package:specular/core/sync/local_store.dart';

import 'local_store_contract.dart';

void main() {
  runLocalStoreContract('InMemoryLocalStore', () async => InMemoryLocalStore());
}
