import 'package:app_template/services/review/review_service.dart';
import 'package:app_template/services/storage/storage_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final Provider<ReviewService> reviewServiceProvider = Provider<ReviewService>(
  (Ref ref) => ReviewService(ref.watch(keyValueStoreProvider)),
);
