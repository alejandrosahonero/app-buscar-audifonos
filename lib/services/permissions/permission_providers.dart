import 'package:buscar_audifonos/services/permissions/permission_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final Provider<PermissionService> permissionServiceProvider =
    Provider<PermissionService>((Ref ref) => const PermissionService());
