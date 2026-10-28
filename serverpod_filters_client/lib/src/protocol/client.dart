/* AUTOMATICALLY GENERATED CODE DO NOT MODIFY */
/*   To generate run: "serverpod generate"    */

// ignore_for_file: implementation_imports
// ignore_for_file: library_private_types_in_public_api
// ignore_for_file: non_constant_identifier_names
// ignore_for_file: public_member_api_docs
// ignore_for_file: type_literal_in_constant_pattern
// ignore_for_file: use_super_parameters
// ignore_for_file: invalid_use_of_internal_member

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'dart:async' as _ida;
import 'package:serverpod_client/serverpod_client.dart' as _isc;

/// {@category Endpoint}
class EndpointModule extends _isc.EndpointRef {
  EndpointModule(_isc.EndpointCaller caller) : super(caller);

  @override
  String get name => 'serverpod_filters.module';

  _ida.Future<String> hello(String name) => caller.callServerEndpoint<String>(
    'serverpod_filters.module',
    'hello',
    {'name': name},
  );
}

class Caller extends _isc.ModuleEndpointCaller {
  Caller(_isc.ServerpodClientShared client) : super(client) {
    module = EndpointModule(this);
  }

  late final EndpointModule module;

  @override
  Map<String, _isc.EndpointRef> get endpointRefLookup => {
    'serverpod_filters.module': module,
  };
}
