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

import 'package:serverpod/serverpod.dart' as _i1;
import 'package:serverpod/protocol.dart' as _i2;
import 'acs.dart' as _i3;
import 'alert.dart' as _i4;
import 'alert_delivery_record.dart' as _i5;
import 'alert_idempotency_key.dart' as _i6;
import 'alert_outbox_entry.dart' as _i7;
import 'api/alert_ack_result.dart' as _i8;
import 'api/alert_status_result.dart' as _i9;
import 'api/development_login_result.dart' as _i10;
import 'api/enrollment_result.dart' as _i11;
import 'api/enrollment_token_result.dart' as _i12;
import 'api/micro_area_patient.dart' as _i13;
import 'api/red_alert_result.dart' as _i14;
import 'api/service_health.dart' as _i15;
import 'api/triage_result.dart' as _i16;
import 'api/visit_sync_entry.dart' as _i17;
import 'api/visit_sync_result.dart' as _i18;
import 'audit_log.dart' as _i19;
import 'consent_log.dart' as _i20;
import 'enrollment_token.dart' as _i21;
import 'enums/alert_status.dart' as _i22;
import 'enums/arrival_method.dart' as _i23;
import 'enums/consent_purpose.dart' as _i24;
import 'enums/risk_level.dart' as _i25;
import 'enums/sync_status.dart' as _i26;
import 'enums/user_role.dart' as _i27;
import 'exceptions/alert_dispatch_unavailable_exception.dart' as _i28;
import 'exceptions/alert_permission_exception.dart' as _i29;
import 'exceptions/alert_validation_exception.dart' as _i30;
import 'exceptions/authentication_failed_exception.dart' as _i31;
import 'exceptions/endpoint_disabled_exception.dart' as _i32;
import 'exceptions/enrollment_exception.dart' as _i33;
import 'exceptions/otp_request_exception.dart' as _i34;
import 'micro_area.dart' as _i35;
import 'otp_challenge.dart' as _i36;
import 'patient.dart' as _i37;
import 'triage_answer.dart' as _i38;
import 'triage_session.dart' as _i39;
import 'ubs.dart' as _i40;
import 'user.dart' as _i41;
import 'user_credential.dart' as _i42;
import 'visit.dart' as _i43;
import 'package:sinalacs_server/src/generated/api/micro_area_patient.dart'
    as _i44;
import 'package:sinalacs_server/src/generated/api/visit_sync_result.dart'
    as _i45;
import 'package:sinalacs_server/src/generated/api/visit_sync_entry.dart'
    as _i46;
export 'acs.dart';
export 'alert.dart';
export 'alert_delivery_record.dart';
export 'alert_idempotency_key.dart';
export 'alert_outbox_entry.dart';
export 'api/alert_ack_result.dart';
export 'api/alert_status_result.dart';
export 'api/development_login_result.dart';
export 'api/enrollment_result.dart';
export 'api/enrollment_token_result.dart';
export 'api/micro_area_patient.dart';
export 'api/red_alert_result.dart';
export 'api/service_health.dart';
export 'api/triage_result.dart';
export 'api/visit_sync_entry.dart';
export 'api/visit_sync_result.dart';
export 'audit_log.dart';
export 'consent_log.dart';
export 'enrollment_token.dart';
export 'enums/alert_status.dart';
export 'enums/arrival_method.dart';
export 'enums/consent_purpose.dart';
export 'enums/risk_level.dart';
export 'enums/sync_status.dart';
export 'enums/user_role.dart';
export 'exceptions/alert_dispatch_unavailable_exception.dart';
export 'exceptions/alert_permission_exception.dart';
export 'exceptions/alert_validation_exception.dart';
export 'exceptions/authentication_failed_exception.dart';
export 'exceptions/endpoint_disabled_exception.dart';
export 'exceptions/enrollment_exception.dart';
export 'exceptions/otp_request_exception.dart';
export 'micro_area.dart';
export 'otp_challenge.dart';
export 'patient.dart';
export 'triage_answer.dart';
export 'triage_session.dart';
export 'ubs.dart';
export 'user.dart';
export 'user_credential.dart';
export 'visit.dart';

class Protocol extends _i1.SerializationManagerServer {
  Protocol._();

  factory Protocol() => _instance;

  static final Protocol _instance = Protocol._();

  static final List<_i2.TableDefinition> targetTableDefinitions = [
    _i2.TableDefinition(
      name: 'acs',
      dartName: 'Acs',
      schema: 'public',
      module: 'sinalacs',
      columns: [
        _i2.ColumnDefinition(
          name: 'id',
          columnType: _i2.ColumnType.uuid,
          isNullable: false,
          dartType: 'UuidValue?',
          columnDefault: 'gen_random_uuid()',
        ),
        _i2.ColumnDefinition(
          name: 'enrollmentId',
          columnType: _i2.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _i2.ColumnDefinition(
          name: 'ubsId',
          columnType: _i2.ColumnType.uuid,
          isNullable: false,
          dartType: 'UuidValue',
        ),
        _i2.ColumnDefinition(
          name: 'active',
          columnType: _i2.ColumnType.boolean,
          isNullable: false,
          dartType: 'bool',
        ),
        _i2.ColumnDefinition(
          name: 'lastSyncAt',
          columnType: _i2.ColumnType.timestampWithoutTimeZone,
          isNullable: true,
          dartType: 'DateTime?',
        ),
      ],
      foreignKeys: [],
      indexes: [
        _i2.IndexDefinition(
          indexName: 'acs_pkey',
          tableSpace: null,
          elements: [
            _i2.IndexElementDefinition(
              type: _i2.IndexElementDefinitionType.column,
              definition: 'id',
            ),
          ],
          type: 'btree',
          isUnique: true,
          isPrimary: true,
        ),
        _i2.IndexDefinition(
          indexName: 'acs_ubs_idx',
          tableSpace: null,
          elements: [
            _i2.IndexElementDefinition(
              type: _i2.IndexElementDefinitionType.column,
              definition: 'ubsId',
            ),
          ],
          type: 'btree',
          isUnique: false,
          isPrimary: false,
        ),
        _i2.IndexDefinition(
          indexName: 'acs_enrollment_id_key',
          tableSpace: null,
          elements: [
            _i2.IndexElementDefinition(
              type: _i2.IndexElementDefinitionType.column,
              definition: 'enrollmentId',
            ),
          ],
          type: 'btree',
          isUnique: true,
          isPrimary: false,
        ),
      ],
      managed: true,
    ),
    _i2.TableDefinition(
      name: 'alert_deliveries',
      dartName: 'AlertDeliveryRecord',
      schema: 'public',
      module: 'sinalacs',
      columns: [
        _i2.ColumnDefinition(
          name: 'id',
          columnType: _i2.ColumnType.uuid,
          isNullable: false,
          dartType: 'UuidValue?',
          columnDefault: 'gen_random_uuid()',
        ),
        _i2.ColumnDefinition(
          name: 'alertId',
          columnType: _i2.ColumnType.uuid,
          isNullable: false,
          dartType: 'UuidValue',
        ),
        _i2.ColumnDefinition(
          name: 'acsId',
          columnType: _i2.ColumnType.uuid,
          isNullable: false,
          dartType: 'UuidValue',
        ),
        _i2.ColumnDefinition(
          name: 'acknowledgedAt',
          columnType: _i2.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
        ),
      ],
      foreignKeys: [
        _i2.ForeignKeyDefinition(
          constraintName: 'alert_deliveries_fk_0',
          columns: ['alertId'],
          referenceTable: 'alerts',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _i2.ForeignKeyAction.noAction,
          onDelete: _i2.ForeignKeyAction.noAction,
          matchType: null,
        ),
        _i2.ForeignKeyDefinition(
          constraintName: 'alert_deliveries_fk_1',
          columns: ['acsId'],
          referenceTable: 'acs',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _i2.ForeignKeyAction.noAction,
          onDelete: _i2.ForeignKeyAction.noAction,
          matchType: null,
        ),
      ],
      indexes: [
        _i2.IndexDefinition(
          indexName: 'alert_deliveries_pkey',
          tableSpace: null,
          elements: [
            _i2.IndexElementDefinition(
              type: _i2.IndexElementDefinitionType.column,
              definition: 'id',
            ),
          ],
          type: 'btree',
          isUnique: true,
          isPrimary: true,
        ),
        _i2.IndexDefinition(
          indexName: 'alert_deliveries_alert_acs_key',
          tableSpace: null,
          elements: [
            _i2.IndexElementDefinition(
              type: _i2.IndexElementDefinitionType.column,
              definition: 'alertId',
            ),
            _i2.IndexElementDefinition(
              type: _i2.IndexElementDefinitionType.column,
              definition: 'acsId',
            ),
          ],
          type: 'btree',
          isUnique: true,
          isPrimary: false,
        ),
      ],
      managed: true,
    ),
    _i2.TableDefinition(
      name: 'alert_idempotency_keys',
      dartName: 'AlertIdempotencyKey',
      schema: 'public',
      module: 'sinalacs',
      columns: [
        _i2.ColumnDefinition(
          name: 'id',
          columnType: _i2.ColumnType.uuid,
          isNullable: false,
          dartType: 'UuidValue?',
          columnDefault: 'gen_random_uuid()',
        ),
        _i2.ColumnDefinition(
          name: 'key',
          columnType: _i2.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _i2.ColumnDefinition(
          name: 'alertId',
          columnType: _i2.ColumnType.uuid,
          isNullable: false,
          dartType: 'UuidValue',
        ),
        _i2.ColumnDefinition(
          name: 'locationHash',
          columnType: _i2.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _i2.ColumnDefinition(
          name: 'createdAt',
          columnType: _i2.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
        ),
      ],
      foreignKeys: [
        _i2.ForeignKeyDefinition(
          constraintName: 'alert_idempotency_keys_fk_0',
          columns: ['alertId'],
          referenceTable: 'alerts',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _i2.ForeignKeyAction.noAction,
          onDelete: _i2.ForeignKeyAction.noAction,
          matchType: null,
        ),
      ],
      indexes: [
        _i2.IndexDefinition(
          indexName: 'alert_idempotency_keys_pkey',
          tableSpace: null,
          elements: [
            _i2.IndexElementDefinition(
              type: _i2.IndexElementDefinitionType.column,
              definition: 'id',
            ),
          ],
          type: 'btree',
          isUnique: true,
          isPrimary: true,
        ),
        _i2.IndexDefinition(
          indexName: 'alert_idempotency_keys_key_key',
          tableSpace: null,
          elements: [
            _i2.IndexElementDefinition(
              type: _i2.IndexElementDefinitionType.column,
              definition: 'key',
            ),
          ],
          type: 'btree',
          isUnique: true,
          isPrimary: false,
        ),
      ],
      managed: true,
    ),
    _i2.TableDefinition(
      name: 'alert_outbox',
      dartName: 'AlertOutboxEntry',
      schema: 'public',
      module: 'sinalacs',
      columns: [
        _i2.ColumnDefinition(
          name: 'id',
          columnType: _i2.ColumnType.uuid,
          isNullable: false,
          dartType: 'UuidValue?',
          columnDefault: 'gen_random_uuid()',
        ),
        _i2.ColumnDefinition(
          name: 'alertId',
          columnType: _i2.ColumnType.uuid,
          isNullable: false,
          dartType: 'UuidValue',
        ),
        _i2.ColumnDefinition(
          name: 'topic',
          columnType: _i2.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _i2.ColumnDefinition(
          name: 'payload',
          columnType: _i2.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _i2.ColumnDefinition(
          name: 'createdAt',
          columnType: _i2.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
        ),
        _i2.ColumnDefinition(
          name: 'publishedAt',
          columnType: _i2.ColumnType.timestampWithoutTimeZone,
          isNullable: true,
          dartType: 'DateTime?',
        ),
        _i2.ColumnDefinition(
          name: 'attempts',
          columnType: _i2.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _i2.ColumnDefinition(
          name: 'nextAttemptAt',
          columnType: _i2.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
        ),
        _i2.ColumnDefinition(
          name: 'lastError',
          columnType: _i2.ColumnType.text,
          isNullable: true,
          dartType: 'String?',
        ),
      ],
      foreignKeys: [
        _i2.ForeignKeyDefinition(
          constraintName: 'alert_outbox_fk_0',
          columns: ['alertId'],
          referenceTable: 'alerts',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _i2.ForeignKeyAction.noAction,
          onDelete: _i2.ForeignKeyAction.noAction,
          matchType: null,
        ),
      ],
      indexes: [
        _i2.IndexDefinition(
          indexName: 'alert_outbox_pkey',
          tableSpace: null,
          elements: [
            _i2.IndexElementDefinition(
              type: _i2.IndexElementDefinitionType.column,
              definition: 'id',
            ),
          ],
          type: 'btree',
          isUnique: true,
          isPrimary: true,
        ),
        _i2.IndexDefinition(
          indexName: 'alert_outbox_pending_idx',
          tableSpace: null,
          elements: [
            _i2.IndexElementDefinition(
              type: _i2.IndexElementDefinitionType.column,
              definition: 'publishedAt',
            ),
            _i2.IndexElementDefinition(
              type: _i2.IndexElementDefinitionType.column,
              definition: 'nextAttemptAt',
            ),
          ],
          type: 'btree',
          isUnique: false,
          isPrimary: false,
        ),
      ],
      managed: true,
    ),
    _i2.TableDefinition(
      name: 'alerts',
      dartName: 'Alert',
      schema: 'public',
      module: 'sinalacs',
      columns: [
        _i2.ColumnDefinition(
          name: 'id',
          columnType: _i2.ColumnType.uuid,
          isNullable: false,
          dartType: 'UuidValue?',
          columnDefault: 'gen_random_uuid()',
        ),
        _i2.ColumnDefinition(
          name: 'patientId',
          columnType: _i2.ColumnType.uuid,
          isNullable: false,
          dartType: 'UuidValue',
        ),
        _i2.ColumnDefinition(
          name: 'acsId',
          columnType: _i2.ColumnType.uuid,
          isNullable: true,
          dartType: 'UuidValue?',
        ),
        _i2.ColumnDefinition(
          name: 'microAreaId',
          columnType: _i2.ColumnType.uuid,
          isNullable: true,
          dartType: 'UuidValue?',
        ),
        _i2.ColumnDefinition(
          name: 'triggeredAt',
          columnType: _i2.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
        ),
        _i2.ColumnDefinition(
          name: 'receivedAt',
          columnType: _i2.ColumnType.timestampWithoutTimeZone,
          isNullable: true,
          dartType: 'DateTime?',
        ),
        _i2.ColumnDefinition(
          name: 'respondedAt',
          columnType: _i2.ColumnType.timestampWithoutTimeZone,
          isNullable: true,
          dartType: 'DateTime?',
        ),
        _i2.ColumnDefinition(
          name: 'acknowledgedAt',
          columnType: _i2.ColumnType.timestampWithoutTimeZone,
          isNullable: true,
          dartType: 'DateTime?',
        ),
        _i2.ColumnDefinition(
          name: 'riskLevel',
          columnType: _i2.ColumnType.text,
          isNullable: false,
          dartType: 'protocol:RiskLevel',
        ),
        _i2.ColumnDefinition(
          name: 'locationHash',
          columnType: _i2.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _i2.ColumnDefinition(
          name: 'locationCell',
          columnType: _i2.ColumnType.text,
          isNullable: true,
          dartType: 'String?',
        ),
        _i2.ColumnDefinition(
          name: 'status',
          columnType: _i2.ColumnType.text,
          isNullable: false,
          dartType: 'protocol:AlertStatus',
        ),
        _i2.ColumnDefinition(
          name: 'mqttTopic',
          columnType: _i2.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _i2.ColumnDefinition(
          name: 'deviceId',
          columnType: _i2.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _i2.ColumnDefinition(
          name: 'retryCount',
          columnType: _i2.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _i2.ColumnDefinition(
          name: 'version',
          columnType: _i2.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
      ],
      foreignKeys: [
        _i2.ForeignKeyDefinition(
          constraintName: 'alerts_fk_0',
          columns: ['patientId'],
          referenceTable: 'patients',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _i2.ForeignKeyAction.noAction,
          onDelete: _i2.ForeignKeyAction.noAction,
          matchType: null,
        ),
        _i2.ForeignKeyDefinition(
          constraintName: 'alerts_fk_1',
          columns: ['acsId'],
          referenceTable: 'acs',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _i2.ForeignKeyAction.noAction,
          onDelete: _i2.ForeignKeyAction.noAction,
          matchType: null,
        ),
      ],
      indexes: [
        _i2.IndexDefinition(
          indexName: 'alerts_pkey',
          tableSpace: null,
          elements: [
            _i2.IndexElementDefinition(
              type: _i2.IndexElementDefinitionType.column,
              definition: 'id',
            ),
          ],
          type: 'btree',
          isUnique: true,
          isPrimary: true,
        ),
        _i2.IndexDefinition(
          indexName: 'alerts_micro_area_status_idx',
          tableSpace: null,
          elements: [
            _i2.IndexElementDefinition(
              type: _i2.IndexElementDefinitionType.column,
              definition: 'microAreaId',
            ),
            _i2.IndexElementDefinition(
              type: _i2.IndexElementDefinitionType.column,
              definition: 'status',
            ),
            _i2.IndexElementDefinition(
              type: _i2.IndexElementDefinitionType.column,
              definition: 'triggeredAt',
            ),
          ],
          type: 'btree',
          isUnique: false,
          isPrimary: false,
        ),
      ],
      managed: true,
    ),
    _i2.TableDefinition(
      name: 'audit_logs',
      dartName: 'AuditLog',
      schema: 'public',
      module: 'sinalacs',
      columns: [
        _i2.ColumnDefinition(
          name: 'id',
          columnType: _i2.ColumnType.uuid,
          isNullable: false,
          dartType: 'UuidValue?',
          columnDefault: 'gen_random_uuid()',
        ),
        _i2.ColumnDefinition(
          name: 'userId',
          columnType: _i2.ColumnType.uuid,
          isNullable: false,
          dartType: 'UuidValue',
        ),
        _i2.ColumnDefinition(
          name: 'actionType',
          columnType: _i2.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _i2.ColumnDefinition(
          name: 'resourceType',
          columnType: _i2.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _i2.ColumnDefinition(
          name: 'resourceId',
          columnType: _i2.ColumnType.uuid,
          isNullable: true,
          dartType: 'UuidValue?',
        ),
        _i2.ColumnDefinition(
          name: 'timestamp',
          columnType: _i2.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
        ),
        _i2.ColumnDefinition(
          name: 'ipHash',
          columnType: _i2.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _i2.ColumnDefinition(
          name: 'result',
          columnType: _i2.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _i2.ColumnDefinition(
          name: 'sequence',
          columnType: _i2.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _i2.ColumnDefinition(
          name: 'previousHash',
          columnType: _i2.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _i2.ColumnDefinition(
          name: 'entryHash',
          columnType: _i2.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
      ],
      foreignKeys: [
        _i2.ForeignKeyDefinition(
          constraintName: 'audit_logs_fk_0',
          columns: ['userId'],
          referenceTable: 'users',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _i2.ForeignKeyAction.noAction,
          onDelete: _i2.ForeignKeyAction.noAction,
          matchType: null,
        ),
      ],
      indexes: [
        _i2.IndexDefinition(
          indexName: 'audit_logs_pkey',
          tableSpace: null,
          elements: [
            _i2.IndexElementDefinition(
              type: _i2.IndexElementDefinitionType.column,
              definition: 'id',
            ),
          ],
          type: 'btree',
          isUnique: true,
          isPrimary: true,
        ),
        _i2.IndexDefinition(
          indexName: 'audit_logs_sequence_idx',
          tableSpace: null,
          elements: [
            _i2.IndexElementDefinition(
              type: _i2.IndexElementDefinitionType.column,
              definition: 'sequence',
            ),
          ],
          type: 'btree',
          isUnique: true,
          isPrimary: false,
        ),
      ],
      managed: true,
    ),
    _i2.TableDefinition(
      name: 'consent_logs',
      dartName: 'ConsentLog',
      schema: 'public',
      module: 'sinalacs',
      columns: [
        _i2.ColumnDefinition(
          name: 'id',
          columnType: _i2.ColumnType.uuid,
          isNullable: false,
          dartType: 'UuidValue?',
          columnDefault: 'gen_random_uuid()',
        ),
        _i2.ColumnDefinition(
          name: 'userId',
          columnType: _i2.ColumnType.uuid,
          isNullable: false,
          dartType: 'UuidValue',
        ),
        _i2.ColumnDefinition(
          name: 'purpose',
          columnType: _i2.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _i2.ColumnDefinition(
          name: 'action',
          columnType: _i2.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _i2.ColumnDefinition(
          name: 'version',
          columnType: _i2.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _i2.ColumnDefinition(
          name: 'timestamp',
          columnType: _i2.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
        ),
        _i2.ColumnDefinition(
          name: 'ipHash',
          columnType: _i2.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _i2.ColumnDefinition(
          name: 'userAgent',
          columnType: _i2.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _i2.ColumnDefinition(
          name: 'signature',
          columnType: _i2.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
      ],
      foreignKeys: [
        _i2.ForeignKeyDefinition(
          constraintName: 'consent_logs_fk_0',
          columns: ['userId'],
          referenceTable: 'users',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _i2.ForeignKeyAction.noAction,
          onDelete: _i2.ForeignKeyAction.noAction,
          matchType: null,
        ),
      ],
      indexes: [
        _i2.IndexDefinition(
          indexName: 'consent_logs_pkey',
          tableSpace: null,
          elements: [
            _i2.IndexElementDefinition(
              type: _i2.IndexElementDefinitionType.column,
              definition: 'id',
            ),
          ],
          type: 'btree',
          isUnique: true,
          isPrimary: true,
        ),
      ],
      managed: true,
    ),
    _i2.TableDefinition(
      name: 'enrollment_tokens',
      dartName: 'EnrollmentToken',
      schema: 'public',
      module: 'sinalacs',
      columns: [
        _i2.ColumnDefinition(
          name: 'id',
          columnType: _i2.ColumnType.uuid,
          isNullable: false,
          dartType: 'UuidValue?',
          columnDefault: 'gen_random_uuid()',
        ),
        _i2.ColumnDefinition(
          name: 'tokenHash',
          columnType: _i2.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _i2.ColumnDefinition(
          name: 'patientId',
          columnType: _i2.ColumnType.uuid,
          isNullable: false,
          dartType: 'UuidValue',
        ),
        _i2.ColumnDefinition(
          name: 'microAreaId',
          columnType: _i2.ColumnType.uuid,
          isNullable: false,
          dartType: 'UuidValue',
        ),
        _i2.ColumnDefinition(
          name: 'createdByAcsId',
          columnType: _i2.ColumnType.uuid,
          isNullable: false,
          dartType: 'UuidValue',
        ),
        _i2.ColumnDefinition(
          name: 'createdAt',
          columnType: _i2.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
        ),
        _i2.ColumnDefinition(
          name: 'expiresAt',
          columnType: _i2.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
        ),
        _i2.ColumnDefinition(
          name: 'consumedAt',
          columnType: _i2.ColumnType.timestampWithoutTimeZone,
          isNullable: true,
          dartType: 'DateTime?',
        ),
      ],
      foreignKeys: [
        _i2.ForeignKeyDefinition(
          constraintName: 'enrollment_tokens_fk_0',
          columns: ['patientId'],
          referenceTable: 'patients',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _i2.ForeignKeyAction.noAction,
          onDelete: _i2.ForeignKeyAction.noAction,
          matchType: null,
        ),
        _i2.ForeignKeyDefinition(
          constraintName: 'enrollment_tokens_fk_1',
          columns: ['createdByAcsId'],
          referenceTable: 'acs',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _i2.ForeignKeyAction.noAction,
          onDelete: _i2.ForeignKeyAction.noAction,
          matchType: null,
        ),
      ],
      indexes: [
        _i2.IndexDefinition(
          indexName: 'enrollment_tokens_pkey',
          tableSpace: null,
          elements: [
            _i2.IndexElementDefinition(
              type: _i2.IndexElementDefinitionType.column,
              definition: 'id',
            ),
          ],
          type: 'btree',
          isUnique: true,
          isPrimary: true,
        ),
        _i2.IndexDefinition(
          indexName: 'enrollment_tokens_token_hash_key',
          tableSpace: null,
          elements: [
            _i2.IndexElementDefinition(
              type: _i2.IndexElementDefinitionType.column,
              definition: 'tokenHash',
            ),
          ],
          type: 'btree',
          isUnique: true,
          isPrimary: false,
        ),
      ],
      managed: true,
    ),
    _i2.TableDefinition(
      name: 'micro_areas',
      dartName: 'MicroArea',
      schema: 'public',
      module: 'sinalacs',
      columns: [
        _i2.ColumnDefinition(
          name: 'id',
          columnType: _i2.ColumnType.uuid,
          isNullable: false,
          dartType: 'UuidValue?',
          columnDefault: 'gen_random_uuid()',
        ),
        _i2.ColumnDefinition(
          name: 'name',
          columnType: _i2.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _i2.ColumnDefinition(
          name: 'ubsId',
          columnType: _i2.ColumnType.uuid,
          isNullable: false,
          dartType: 'UuidValue',
        ),
        _i2.ColumnDefinition(
          name: 'geoJsonBoundary',
          columnType: _i2.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
      ],
      foreignKeys: [],
      indexes: [
        _i2.IndexDefinition(
          indexName: 'micro_areas_pkey',
          tableSpace: null,
          elements: [
            _i2.IndexElementDefinition(
              type: _i2.IndexElementDefinitionType.column,
              definition: 'id',
            ),
          ],
          type: 'btree',
          isUnique: true,
          isPrimary: true,
        ),
        _i2.IndexDefinition(
          indexName: 'micro_areas_ubs_idx',
          tableSpace: null,
          elements: [
            _i2.IndexElementDefinition(
              type: _i2.IndexElementDefinitionType.column,
              definition: 'ubsId',
            ),
          ],
          type: 'btree',
          isUnique: false,
          isPrimary: false,
        ),
      ],
      managed: true,
    ),
    _i2.TableDefinition(
      name: 'otp_challenges',
      dartName: 'OtpChallenge',
      schema: 'public',
      module: 'sinalacs',
      columns: [
        _i2.ColumnDefinition(
          name: 'id',
          columnType: _i2.ColumnType.uuid,
          isNullable: false,
          dartType: 'UuidValue?',
          columnDefault: 'gen_random_uuid()',
        ),
        _i2.ColumnDefinition(
          name: 'userId',
          columnType: _i2.ColumnType.uuid,
          isNullable: false,
          dartType: 'UuidValue',
        ),
        _i2.ColumnDefinition(
          name: 'codeHash',
          columnType: _i2.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _i2.ColumnDefinition(
          name: 'attempts',
          columnType: _i2.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _i2.ColumnDefinition(
          name: 'createdAt',
          columnType: _i2.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
        ),
        _i2.ColumnDefinition(
          name: 'expiresAt',
          columnType: _i2.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
        ),
        _i2.ColumnDefinition(
          name: 'consumedAt',
          columnType: _i2.ColumnType.timestampWithoutTimeZone,
          isNullable: true,
          dartType: 'DateTime?',
        ),
      ],
      foreignKeys: [
        _i2.ForeignKeyDefinition(
          constraintName: 'otp_challenges_fk_0',
          columns: ['userId'],
          referenceTable: 'users',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _i2.ForeignKeyAction.noAction,
          onDelete: _i2.ForeignKeyAction.noAction,
          matchType: null,
        ),
      ],
      indexes: [
        _i2.IndexDefinition(
          indexName: 'otp_challenges_pkey',
          tableSpace: null,
          elements: [
            _i2.IndexElementDefinition(
              type: _i2.IndexElementDefinitionType.column,
              definition: 'id',
            ),
          ],
          type: 'btree',
          isUnique: true,
          isPrimary: true,
        ),
        _i2.IndexDefinition(
          indexName: 'otp_challenges_user_id_created_at_idx',
          tableSpace: null,
          elements: [
            _i2.IndexElementDefinition(
              type: _i2.IndexElementDefinitionType.column,
              definition: 'userId',
            ),
            _i2.IndexElementDefinition(
              type: _i2.IndexElementDefinitionType.column,
              definition: 'createdAt',
            ),
          ],
          type: 'btree',
          isUnique: false,
          isPrimary: false,
        ),
      ],
      managed: true,
    ),
    _i2.TableDefinition(
      name: 'patients',
      dartName: 'Patient',
      schema: 'public',
      module: 'sinalacs',
      columns: [
        _i2.ColumnDefinition(
          name: 'id',
          columnType: _i2.ColumnType.uuid,
          isNullable: false,
          dartType: 'UuidValue?',
          columnDefault: 'gen_random_uuid()',
        ),
        _i2.ColumnDefinition(
          name: 'emergencyContact',
          columnType: _i2.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _i2.ColumnDefinition(
          name: 'isChronic',
          columnType: _i2.ColumnType.boolean,
          isNullable: false,
          dartType: 'bool',
        ),
        _i2.ColumnDefinition(
          name: 'chronicConditionsEncrypted',
          columnType: _i2.ColumnType.text,
          isNullable: false,
          dartType: 'String',
          columnDefault: '\'\'::text',
        ),
        _i2.ColumnDefinition(
          name: 'chronicConditionsKeyVersion',
          columnType: _i2.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
          columnDefault: '1',
        ),
        _i2.ColumnDefinition(
          name: 'lastLocationHash',
          columnType: _i2.ColumnType.text,
          isNullable: true,
          dartType: 'String?',
        ),
        _i2.ColumnDefinition(
          name: 'lastTriageAt',
          columnType: _i2.ColumnType.timestampWithoutTimeZone,
          isNullable: true,
          dartType: 'DateTime?',
        ),
      ],
      foreignKeys: [],
      indexes: [
        _i2.IndexDefinition(
          indexName: 'patients_pkey',
          tableSpace: null,
          elements: [
            _i2.IndexElementDefinition(
              type: _i2.IndexElementDefinitionType.column,
              definition: 'id',
            ),
          ],
          type: 'btree',
          isUnique: true,
          isPrimary: true,
        ),
      ],
      managed: true,
    ),
    _i2.TableDefinition(
      name: 'triage_sessions',
      dartName: 'TriageSession',
      schema: 'public',
      module: 'sinalacs',
      columns: [
        _i2.ColumnDefinition(
          name: 'id',
          columnType: _i2.ColumnType.uuid,
          isNullable: false,
          dartType: 'UuidValue?',
          columnDefault: 'gen_random_uuid()',
        ),
        _i2.ColumnDefinition(
          name: 'patientId',
          columnType: _i2.ColumnType.uuid,
          isNullable: false,
          dartType: 'UuidValue',
        ),
        _i2.ColumnDefinition(
          name: 'answersEncrypted',
          columnType: _i2.ColumnType.text,
          isNullable: false,
          dartType: 'String',
          columnDefault: '\'\'::text',
        ),
        _i2.ColumnDefinition(
          name: 'answersKeyVersion',
          columnType: _i2.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
          columnDefault: '1',
        ),
        _i2.ColumnDefinition(
          name: 'resultRisk',
          columnType: _i2.ColumnType.text,
          isNullable: false,
          dartType: 'protocol:RiskLevel',
        ),
        _i2.ColumnDefinition(
          name: 'resultDisplay',
          columnType: _i2.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _i2.ColumnDefinition(
          name: 'createdAt',
          columnType: _i2.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
        ),
        _i2.ColumnDefinition(
          name: 'deviceId',
          columnType: _i2.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
      ],
      foreignKeys: [
        _i2.ForeignKeyDefinition(
          constraintName: 'triage_sessions_fk_0',
          columns: ['patientId'],
          referenceTable: 'patients',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _i2.ForeignKeyAction.noAction,
          onDelete: _i2.ForeignKeyAction.noAction,
          matchType: null,
        ),
      ],
      indexes: [
        _i2.IndexDefinition(
          indexName: 'triage_sessions_pkey',
          tableSpace: null,
          elements: [
            _i2.IndexElementDefinition(
              type: _i2.IndexElementDefinitionType.column,
              definition: 'id',
            ),
          ],
          type: 'btree',
          isUnique: true,
          isPrimary: true,
        ),
      ],
      managed: true,
    ),
    _i2.TableDefinition(
      name: 'ubs',
      dartName: 'Ubs',
      schema: 'public',
      module: 'sinalacs',
      columns: [
        _i2.ColumnDefinition(
          name: 'id',
          columnType: _i2.ColumnType.uuid,
          isNullable: false,
          dartType: 'UuidValue?',
          columnDefault: 'gen_random_uuid()',
        ),
        _i2.ColumnDefinition(
          name: 'name',
          columnType: _i2.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _i2.ColumnDefinition(
          name: 'address',
          columnType: _i2.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _i2.ColumnDefinition(
          name: 'city',
          columnType: _i2.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _i2.ColumnDefinition(
          name: 'state',
          columnType: _i2.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
      ],
      foreignKeys: [],
      indexes: [
        _i2.IndexDefinition(
          indexName: 'ubs_pkey',
          tableSpace: null,
          elements: [
            _i2.IndexElementDefinition(
              type: _i2.IndexElementDefinitionType.column,
              definition: 'id',
            ),
          ],
          type: 'btree',
          isUnique: true,
          isPrimary: true,
        ),
      ],
      managed: true,
    ),
    _i2.TableDefinition(
      name: 'user_credentials',
      dartName: 'UserCredential',
      schema: 'public',
      module: 'sinalacs',
      columns: [
        _i2.ColumnDefinition(
          name: 'id',
          columnType: _i2.ColumnType.uuid,
          isNullable: false,
          dartType: 'UuidValue?',
          columnDefault: 'gen_random_uuid()',
        ),
        _i2.ColumnDefinition(
          name: 'userId',
          columnType: _i2.ColumnType.uuid,
          isNullable: false,
          dartType: 'UuidValue',
        ),
        _i2.ColumnDefinition(
          name: 'passwordHash',
          columnType: _i2.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _i2.ColumnDefinition(
          name: 'passwordSalt',
          columnType: _i2.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _i2.ColumnDefinition(
          name: 'memoryKb',
          columnType: _i2.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _i2.ColumnDefinition(
          name: 'iterations',
          columnType: _i2.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _i2.ColumnDefinition(
          name: 'parallelism',
          columnType: _i2.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _i2.ColumnDefinition(
          name: 'failedAttempts',
          columnType: _i2.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _i2.ColumnDefinition(
          name: 'lockedUntil',
          columnType: _i2.ColumnType.timestampWithoutTimeZone,
          isNullable: true,
          dartType: 'DateTime?',
        ),
        _i2.ColumnDefinition(
          name: 'createdAt',
          columnType: _i2.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
        ),
        _i2.ColumnDefinition(
          name: 'updatedAt',
          columnType: _i2.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
        ),
      ],
      foreignKeys: [
        _i2.ForeignKeyDefinition(
          constraintName: 'user_credentials_fk_0',
          columns: ['userId'],
          referenceTable: 'users',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _i2.ForeignKeyAction.noAction,
          onDelete: _i2.ForeignKeyAction.noAction,
          matchType: null,
        ),
      ],
      indexes: [
        _i2.IndexDefinition(
          indexName: 'user_credentials_pkey',
          tableSpace: null,
          elements: [
            _i2.IndexElementDefinition(
              type: _i2.IndexElementDefinitionType.column,
              definition: 'id',
            ),
          ],
          type: 'btree',
          isUnique: true,
          isPrimary: true,
        ),
        _i2.IndexDefinition(
          indexName: 'user_credentials_user_id_key',
          tableSpace: null,
          elements: [
            _i2.IndexElementDefinition(
              type: _i2.IndexElementDefinitionType.column,
              definition: 'userId',
            ),
          ],
          type: 'btree',
          isUnique: true,
          isPrimary: false,
        ),
      ],
      managed: true,
    ),
    _i2.TableDefinition(
      name: 'users',
      dartName: 'User',
      schema: 'public',
      module: 'sinalacs',
      columns: [
        _i2.ColumnDefinition(
          name: 'id',
          columnType: _i2.ColumnType.uuid,
          isNullable: false,
          dartType: 'UuidValue?',
          columnDefault: 'gen_random_uuid()',
        ),
        _i2.ColumnDefinition(
          name: 'cpfHash',
          columnType: _i2.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _i2.ColumnDefinition(
          name: 'name',
          columnType: _i2.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _i2.ColumnDefinition(
          name: 'birthDate',
          columnType: _i2.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
        ),
        _i2.ColumnDefinition(
          name: 'role',
          columnType: _i2.ColumnType.text,
          isNullable: false,
          dartType: 'protocol:UserRole',
        ),
        _i2.ColumnDefinition(
          name: 'microAreaId',
          columnType: _i2.ColumnType.uuid,
          isNullable: true,
          dartType: 'UuidValue?',
        ),
        _i2.ColumnDefinition(
          name: 'createdAt',
          columnType: _i2.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
        ),
        _i2.ColumnDefinition(
          name: 'updatedAt',
          columnType: _i2.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
        ),
      ],
      foreignKeys: [],
      indexes: [
        _i2.IndexDefinition(
          indexName: 'users_pkey',
          tableSpace: null,
          elements: [
            _i2.IndexElementDefinition(
              type: _i2.IndexElementDefinitionType.column,
              definition: 'id',
            ),
          ],
          type: 'btree',
          isUnique: true,
          isPrimary: true,
        ),
        _i2.IndexDefinition(
          indexName: 'users_cpf_hash_key',
          tableSpace: null,
          elements: [
            _i2.IndexElementDefinition(
              type: _i2.IndexElementDefinitionType.column,
              definition: 'cpfHash',
            ),
          ],
          type: 'btree',
          isUnique: true,
          isPrimary: false,
        ),
        _i2.IndexDefinition(
          indexName: 'users_micro_area_idx',
          tableSpace: null,
          elements: [
            _i2.IndexElementDefinition(
              type: _i2.IndexElementDefinitionType.column,
              definition: 'microAreaId',
            ),
          ],
          type: 'btree',
          isUnique: false,
          isPrimary: false,
        ),
      ],
      managed: true,
    ),
    _i2.TableDefinition(
      name: 'visits',
      dartName: 'Visit',
      schema: 'public',
      module: 'sinalacs',
      columns: [
        _i2.ColumnDefinition(
          name: 'id',
          columnType: _i2.ColumnType.uuid,
          isNullable: false,
          dartType: 'UuidValue?',
          columnDefault: 'gen_random_uuid()',
        ),
        _i2.ColumnDefinition(
          name: 'patientId',
          columnType: _i2.ColumnType.uuid,
          isNullable: false,
          dartType: 'UuidValue',
        ),
        _i2.ColumnDefinition(
          name: 'acsId',
          columnType: _i2.ColumnType.uuid,
          isNullable: false,
          dartType: 'UuidValue',
        ),
        _i2.ColumnDefinition(
          name: 'scheduledAt',
          columnType: _i2.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
        ),
        _i2.ColumnDefinition(
          name: 'startedAt',
          columnType: _i2.ColumnType.timestampWithoutTimeZone,
          isNullable: true,
          dartType: 'DateTime?',
        ),
        _i2.ColumnDefinition(
          name: 'completedAt',
          columnType: _i2.ColumnType.timestampWithoutTimeZone,
          isNullable: true,
          dartType: 'DateTime?',
        ),
        _i2.ColumnDefinition(
          name: 'status',
          columnType: _i2.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _i2.ColumnDefinition(
          name: 'riskLevelBefore',
          columnType: _i2.ColumnType.text,
          isNullable: false,
          dartType: 'protocol:RiskLevel',
        ),
        _i2.ColumnDefinition(
          name: 'riskLevelAfter',
          columnType: _i2.ColumnType.text,
          isNullable: true,
          dartType: 'protocol:RiskLevel?',
        ),
        _i2.ColumnDefinition(
          name: 'notesEncrypted',
          columnType: _i2.ColumnType.text,
          isNullable: false,
          dartType: 'String',
          columnDefault: '\'\'::text',
        ),
        _i2.ColumnDefinition(
          name: 'notesKeyVersion',
          columnType: _i2.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
          columnDefault: '1',
        ),
        _i2.ColumnDefinition(
          name: 'syncStatus',
          columnType: _i2.ColumnType.text,
          isNullable: false,
          dartType: 'protocol:SyncStatus',
        ),
        _i2.ColumnDefinition(
          name: 'arrivalMethod',
          columnType: _i2.ColumnType.text,
          isNullable: false,
          dartType: 'protocol:ArrivalMethod',
          columnDefault: '\'manual\'::text',
        ),
        _i2.ColumnDefinition(
          name: 'localId',
          columnType: _i2.ColumnType.uuid,
          isNullable: false,
          dartType: 'UuidValue',
        ),
        _i2.ColumnDefinition(
          name: 'syncAt',
          columnType: _i2.ColumnType.timestampWithoutTimeZone,
          isNullable: true,
          dartType: 'DateTime?',
        ),
        _i2.ColumnDefinition(
          name: 'version',
          columnType: _i2.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
      ],
      foreignKeys: [
        _i2.ForeignKeyDefinition(
          constraintName: 'visits_fk_0',
          columns: ['patientId'],
          referenceTable: 'patients',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _i2.ForeignKeyAction.noAction,
          onDelete: _i2.ForeignKeyAction.noAction,
          matchType: null,
        ),
        _i2.ForeignKeyDefinition(
          constraintName: 'visits_fk_1',
          columns: ['acsId'],
          referenceTable: 'acs',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _i2.ForeignKeyAction.noAction,
          onDelete: _i2.ForeignKeyAction.noAction,
          matchType: null,
        ),
      ],
      indexes: [
        _i2.IndexDefinition(
          indexName: 'visits_pkey',
          tableSpace: null,
          elements: [
            _i2.IndexElementDefinition(
              type: _i2.IndexElementDefinitionType.column,
              definition: 'id',
            ),
          ],
          type: 'btree',
          isUnique: true,
          isPrimary: true,
        ),
        _i2.IndexDefinition(
          indexName: 'visits_local_id_key',
          tableSpace: null,
          elements: [
            _i2.IndexElementDefinition(
              type: _i2.IndexElementDefinitionType.column,
              definition: 'localId',
            ),
          ],
          type: 'btree',
          isUnique: true,
          isPrimary: false,
        ),
      ],
      managed: true,
    ),
    ..._i2.Protocol.targetTableDefinitions,
  ];

  static String? getClassNameFromObjectJson(dynamic data) {
    if (data is! Map) return null;
    final className = data['__className__'] as String?;
    return className;
  }

  @override
  T deserialize<T>(
    dynamic data, [
    Type? t,
  ]) {
    t ??= T;

    final dataClassName = getClassNameFromObjectJson(data);
    if (dataClassName != null && dataClassName != getClassNameForType(t)) {
      try {
        return deserializeByClassName({
          'className': dataClassName,
          'data': data,
        });
      } on FormatException catch (_) {
        // If the className is not recognized (e.g., older client receiving
        // data with a new subtype), fall back to deserializing without the
        // className, using the expected type T.
      }
    }

    if (t == _i3.Acs) {
      return _i3.Acs.fromJson(data) as T;
    }
    if (t == _i4.Alert) {
      return _i4.Alert.fromJson(data) as T;
    }
    if (t == _i5.AlertDeliveryRecord) {
      return _i5.AlertDeliveryRecord.fromJson(data) as T;
    }
    if (t == _i6.AlertIdempotencyKey) {
      return _i6.AlertIdempotencyKey.fromJson(data) as T;
    }
    if (t == _i7.AlertOutboxEntry) {
      return _i7.AlertOutboxEntry.fromJson(data) as T;
    }
    if (t == _i8.AlertAckResult) {
      return _i8.AlertAckResult.fromJson(data) as T;
    }
    if (t == _i9.AlertStatusResult) {
      return _i9.AlertStatusResult.fromJson(data) as T;
    }
    if (t == _i10.DevelopmentLoginResult) {
      return _i10.DevelopmentLoginResult.fromJson(data) as T;
    }
    if (t == _i11.EnrollmentResult) {
      return _i11.EnrollmentResult.fromJson(data) as T;
    }
    if (t == _i12.EnrollmentTokenResult) {
      return _i12.EnrollmentTokenResult.fromJson(data) as T;
    }
    if (t == _i13.MicroAreaPatient) {
      return _i13.MicroAreaPatient.fromJson(data) as T;
    }
    if (t == _i14.RedAlertResult) {
      return _i14.RedAlertResult.fromJson(data) as T;
    }
    if (t == _i15.ServiceHealth) {
      return _i15.ServiceHealth.fromJson(data) as T;
    }
    if (t == _i16.TriageResult) {
      return _i16.TriageResult.fromJson(data) as T;
    }
    if (t == _i17.VisitSyncEntry) {
      return _i17.VisitSyncEntry.fromJson(data) as T;
    }
    if (t == _i18.VisitSyncResult) {
      return _i18.VisitSyncResult.fromJson(data) as T;
    }
    if (t == _i19.AuditLog) {
      return _i19.AuditLog.fromJson(data) as T;
    }
    if (t == _i20.ConsentLog) {
      return _i20.ConsentLog.fromJson(data) as T;
    }
    if (t == _i21.EnrollmentToken) {
      return _i21.EnrollmentToken.fromJson(data) as T;
    }
    if (t == _i22.AlertStatus) {
      return _i22.AlertStatus.fromJson(data) as T;
    }
    if (t == _i23.ArrivalMethod) {
      return _i23.ArrivalMethod.fromJson(data) as T;
    }
    if (t == _i24.ConsentPurpose) {
      return _i24.ConsentPurpose.fromJson(data) as T;
    }
    if (t == _i25.RiskLevel) {
      return _i25.RiskLevel.fromJson(data) as T;
    }
    if (t == _i26.SyncStatus) {
      return _i26.SyncStatus.fromJson(data) as T;
    }
    if (t == _i27.UserRole) {
      return _i27.UserRole.fromJson(data) as T;
    }
    if (t == _i28.AlertDispatchUnavailableException) {
      return _i28.AlertDispatchUnavailableException.fromJson(data) as T;
    }
    if (t == _i29.AlertPermissionException) {
      return _i29.AlertPermissionException.fromJson(data) as T;
    }
    if (t == _i30.AlertValidationException) {
      return _i30.AlertValidationException.fromJson(data) as T;
    }
    if (t == _i31.AuthenticationFailedException) {
      return _i31.AuthenticationFailedException.fromJson(data) as T;
    }
    if (t == _i32.EndpointDisabledException) {
      return _i32.EndpointDisabledException.fromJson(data) as T;
    }
    if (t == _i33.EnrollmentException) {
      return _i33.EnrollmentException.fromJson(data) as T;
    }
    if (t == _i34.OtpRequestException) {
      return _i34.OtpRequestException.fromJson(data) as T;
    }
    if (t == _i35.MicroArea) {
      return _i35.MicroArea.fromJson(data) as T;
    }
    if (t == _i36.OtpChallenge) {
      return _i36.OtpChallenge.fromJson(data) as T;
    }
    if (t == _i37.Patient) {
      return _i37.Patient.fromJson(data) as T;
    }
    if (t == _i38.TriageAnswer) {
      return _i38.TriageAnswer.fromJson(data) as T;
    }
    if (t == _i39.TriageSession) {
      return _i39.TriageSession.fromJson(data) as T;
    }
    if (t == _i40.Ubs) {
      return _i40.Ubs.fromJson(data) as T;
    }
    if (t == _i41.User) {
      return _i41.User.fromJson(data) as T;
    }
    if (t == _i42.UserCredential) {
      return _i42.UserCredential.fromJson(data) as T;
    }
    if (t == _i43.Visit) {
      return _i43.Visit.fromJson(data) as T;
    }
    if (t == _i1.getType<_i3.Acs?>()) {
      return (data != null ? _i3.Acs.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i4.Alert?>()) {
      return (data != null ? _i4.Alert.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i5.AlertDeliveryRecord?>()) {
      return (data != null ? _i5.AlertDeliveryRecord.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i6.AlertIdempotencyKey?>()) {
      return (data != null ? _i6.AlertIdempotencyKey.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i7.AlertOutboxEntry?>()) {
      return (data != null ? _i7.AlertOutboxEntry.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i8.AlertAckResult?>()) {
      return (data != null ? _i8.AlertAckResult.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i9.AlertStatusResult?>()) {
      return (data != null ? _i9.AlertStatusResult.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i10.DevelopmentLoginResult?>()) {
      return (data != null ? _i10.DevelopmentLoginResult.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i11.EnrollmentResult?>()) {
      return (data != null ? _i11.EnrollmentResult.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i12.EnrollmentTokenResult?>()) {
      return (data != null ? _i12.EnrollmentTokenResult.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i13.MicroAreaPatient?>()) {
      return (data != null ? _i13.MicroAreaPatient.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i14.RedAlertResult?>()) {
      return (data != null ? _i14.RedAlertResult.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i15.ServiceHealth?>()) {
      return (data != null ? _i15.ServiceHealth.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i16.TriageResult?>()) {
      return (data != null ? _i16.TriageResult.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i17.VisitSyncEntry?>()) {
      return (data != null ? _i17.VisitSyncEntry.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i18.VisitSyncResult?>()) {
      return (data != null ? _i18.VisitSyncResult.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i19.AuditLog?>()) {
      return (data != null ? _i19.AuditLog.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i20.ConsentLog?>()) {
      return (data != null ? _i20.ConsentLog.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i21.EnrollmentToken?>()) {
      return (data != null ? _i21.EnrollmentToken.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i22.AlertStatus?>()) {
      return (data != null ? _i22.AlertStatus.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i23.ArrivalMethod?>()) {
      return (data != null ? _i23.ArrivalMethod.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i24.ConsentPurpose?>()) {
      return (data != null ? _i24.ConsentPurpose.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i25.RiskLevel?>()) {
      return (data != null ? _i25.RiskLevel.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i26.SyncStatus?>()) {
      return (data != null ? _i26.SyncStatus.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i27.UserRole?>()) {
      return (data != null ? _i27.UserRole.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i28.AlertDispatchUnavailableException?>()) {
      return (data != null
              ? _i28.AlertDispatchUnavailableException.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i29.AlertPermissionException?>()) {
      return (data != null
              ? _i29.AlertPermissionException.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i30.AlertValidationException?>()) {
      return (data != null
              ? _i30.AlertValidationException.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i31.AuthenticationFailedException?>()) {
      return (data != null
              ? _i31.AuthenticationFailedException.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i32.EndpointDisabledException?>()) {
      return (data != null
              ? _i32.EndpointDisabledException.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i33.EnrollmentException?>()) {
      return (data != null ? _i33.EnrollmentException.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i34.OtpRequestException?>()) {
      return (data != null ? _i34.OtpRequestException.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i35.MicroArea?>()) {
      return (data != null ? _i35.MicroArea.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i36.OtpChallenge?>()) {
      return (data != null ? _i36.OtpChallenge.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i37.Patient?>()) {
      return (data != null ? _i37.Patient.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i38.TriageAnswer?>()) {
      return (data != null ? _i38.TriageAnswer.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i39.TriageSession?>()) {
      return (data != null ? _i39.TriageSession.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i40.Ubs?>()) {
      return (data != null ? _i40.Ubs.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i41.User?>()) {
      return (data != null ? _i41.User.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i42.UserCredential?>()) {
      return (data != null ? _i42.UserCredential.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i43.Visit?>()) {
      return (data != null ? _i43.Visit.fromJson(data) : null) as T;
    }
    if (t == List<String>) {
      return (data as List).map((e) => deserialize<String>(e)).toList() as T;
    }
    if (t == Map<String, String>) {
      return (data as Map).map(
            (k, v) => MapEntry(deserialize<String>(k), deserialize<String>(v)),
          )
          as T;
    }
    if (t == List<_i44.MicroAreaPatient>) {
      return (data as List)
              .map((e) => deserialize<_i44.MicroAreaPatient>(e))
              .toList()
          as T;
    }
    if (t == List<_i45.VisitSyncResult>) {
      return (data as List)
              .map((e) => deserialize<_i45.VisitSyncResult>(e))
              .toList()
          as T;
    }
    if (t == List<_i46.VisitSyncEntry>) {
      return (data as List)
              .map((e) => deserialize<_i46.VisitSyncEntry>(e))
              .toList()
          as T;
    }
    try {
      return _i2.Protocol().deserialize<T>(data, t);
    } on _i1.DeserializationTypeNotFoundException catch (_) {}
    return super.deserialize<T>(data, t);
  }

  static String? getClassNameForType(Type type) {
    return switch (type) {
      _i3.Acs => 'Acs',
      _i4.Alert => 'Alert',
      _i5.AlertDeliveryRecord => 'AlertDeliveryRecord',
      _i6.AlertIdempotencyKey => 'AlertIdempotencyKey',
      _i7.AlertOutboxEntry => 'AlertOutboxEntry',
      _i8.AlertAckResult => 'AlertAckResult',
      _i9.AlertStatusResult => 'AlertStatusResult',
      _i10.DevelopmentLoginResult => 'DevelopmentLoginResult',
      _i11.EnrollmentResult => 'EnrollmentResult',
      _i12.EnrollmentTokenResult => 'EnrollmentTokenResult',
      _i13.MicroAreaPatient => 'MicroAreaPatient',
      _i14.RedAlertResult => 'RedAlertResult',
      _i15.ServiceHealth => 'ServiceHealth',
      _i16.TriageResult => 'TriageResult',
      _i17.VisitSyncEntry => 'VisitSyncEntry',
      _i18.VisitSyncResult => 'VisitSyncResult',
      _i19.AuditLog => 'AuditLog',
      _i20.ConsentLog => 'ConsentLog',
      _i21.EnrollmentToken => 'EnrollmentToken',
      _i22.AlertStatus => 'AlertStatus',
      _i23.ArrivalMethod => 'ArrivalMethod',
      _i24.ConsentPurpose => 'ConsentPurpose',
      _i25.RiskLevel => 'RiskLevel',
      _i26.SyncStatus => 'SyncStatus',
      _i27.UserRole => 'UserRole',
      _i28.AlertDispatchUnavailableException =>
        'AlertDispatchUnavailableException',
      _i29.AlertPermissionException => 'AlertPermissionException',
      _i30.AlertValidationException => 'AlertValidationException',
      _i31.AuthenticationFailedException => 'AuthenticationFailedException',
      _i32.EndpointDisabledException => 'EndpointDisabledException',
      _i33.EnrollmentException => 'EnrollmentException',
      _i34.OtpRequestException => 'OtpRequestException',
      _i35.MicroArea => 'MicroArea',
      _i36.OtpChallenge => 'OtpChallenge',
      _i37.Patient => 'Patient',
      _i38.TriageAnswer => 'TriageAnswer',
      _i39.TriageSession => 'TriageSession',
      _i40.Ubs => 'Ubs',
      _i41.User => 'User',
      _i42.UserCredential => 'UserCredential',
      _i43.Visit => 'Visit',
      _ => null,
    };
  }

  @override
  String? getClassNameForObject(Object? data) {
    String? className = super.getClassNameForObject(data);
    if (className != null) return className;

    if (data is Map<String, dynamic> && data['__className__'] is String) {
      return (data['__className__'] as String).replaceFirst('sinalacs.', '');
    }

    switch (data) {
      case _i3.Acs():
        return 'Acs';
      case _i4.Alert():
        return 'Alert';
      case _i5.AlertDeliveryRecord():
        return 'AlertDeliveryRecord';
      case _i6.AlertIdempotencyKey():
        return 'AlertIdempotencyKey';
      case _i7.AlertOutboxEntry():
        return 'AlertOutboxEntry';
      case _i8.AlertAckResult():
        return 'AlertAckResult';
      case _i9.AlertStatusResult():
        return 'AlertStatusResult';
      case _i10.DevelopmentLoginResult():
        return 'DevelopmentLoginResult';
      case _i11.EnrollmentResult():
        return 'EnrollmentResult';
      case _i12.EnrollmentTokenResult():
        return 'EnrollmentTokenResult';
      case _i13.MicroAreaPatient():
        return 'MicroAreaPatient';
      case _i14.RedAlertResult():
        return 'RedAlertResult';
      case _i15.ServiceHealth():
        return 'ServiceHealth';
      case _i16.TriageResult():
        return 'TriageResult';
      case _i17.VisitSyncEntry():
        return 'VisitSyncEntry';
      case _i18.VisitSyncResult():
        return 'VisitSyncResult';
      case _i19.AuditLog():
        return 'AuditLog';
      case _i20.ConsentLog():
        return 'ConsentLog';
      case _i21.EnrollmentToken():
        return 'EnrollmentToken';
      case _i22.AlertStatus():
        return 'AlertStatus';
      case _i23.ArrivalMethod():
        return 'ArrivalMethod';
      case _i24.ConsentPurpose():
        return 'ConsentPurpose';
      case _i25.RiskLevel():
        return 'RiskLevel';
      case _i26.SyncStatus():
        return 'SyncStatus';
      case _i27.UserRole():
        return 'UserRole';
      case _i28.AlertDispatchUnavailableException():
        return 'AlertDispatchUnavailableException';
      case _i29.AlertPermissionException():
        return 'AlertPermissionException';
      case _i30.AlertValidationException():
        return 'AlertValidationException';
      case _i31.AuthenticationFailedException():
        return 'AuthenticationFailedException';
      case _i32.EndpointDisabledException():
        return 'EndpointDisabledException';
      case _i33.EnrollmentException():
        return 'EnrollmentException';
      case _i34.OtpRequestException():
        return 'OtpRequestException';
      case _i35.MicroArea():
        return 'MicroArea';
      case _i36.OtpChallenge():
        return 'OtpChallenge';
      case _i37.Patient():
        return 'Patient';
      case _i38.TriageAnswer():
        return 'TriageAnswer';
      case _i39.TriageSession():
        return 'TriageSession';
      case _i40.Ubs():
        return 'Ubs';
      case _i41.User():
        return 'User';
      case _i42.UserCredential():
        return 'UserCredential';
      case _i43.Visit():
        return 'Visit';
    }
    className = _i2.Protocol().getClassNameForObject(data);
    if (className != null) {
      return 'serverpod.$className';
    }
    return null;
  }

  @override
  dynamic deserializeByClassName(Map<String, dynamic> data) {
    var dataClassName = data['className'];
    if (dataClassName is! String) {
      return super.deserializeByClassName(data);
    }
    if (dataClassName == 'Acs') {
      return deserialize<_i3.Acs>(data['data']);
    }
    if (dataClassName == 'Alert') {
      return deserialize<_i4.Alert>(data['data']);
    }
    if (dataClassName == 'AlertDeliveryRecord') {
      return deserialize<_i5.AlertDeliveryRecord>(data['data']);
    }
    if (dataClassName == 'AlertIdempotencyKey') {
      return deserialize<_i6.AlertIdempotencyKey>(data['data']);
    }
    if (dataClassName == 'AlertOutboxEntry') {
      return deserialize<_i7.AlertOutboxEntry>(data['data']);
    }
    if (dataClassName == 'AlertAckResult') {
      return deserialize<_i8.AlertAckResult>(data['data']);
    }
    if (dataClassName == 'AlertStatusResult') {
      return deserialize<_i9.AlertStatusResult>(data['data']);
    }
    if (dataClassName == 'DevelopmentLoginResult') {
      return deserialize<_i10.DevelopmentLoginResult>(data['data']);
    }
    if (dataClassName == 'EnrollmentResult') {
      return deserialize<_i11.EnrollmentResult>(data['data']);
    }
    if (dataClassName == 'EnrollmentTokenResult') {
      return deserialize<_i12.EnrollmentTokenResult>(data['data']);
    }
    if (dataClassName == 'MicroAreaPatient') {
      return deserialize<_i13.MicroAreaPatient>(data['data']);
    }
    if (dataClassName == 'RedAlertResult') {
      return deserialize<_i14.RedAlertResult>(data['data']);
    }
    if (dataClassName == 'ServiceHealth') {
      return deserialize<_i15.ServiceHealth>(data['data']);
    }
    if (dataClassName == 'TriageResult') {
      return deserialize<_i16.TriageResult>(data['data']);
    }
    if (dataClassName == 'VisitSyncEntry') {
      return deserialize<_i17.VisitSyncEntry>(data['data']);
    }
    if (dataClassName == 'VisitSyncResult') {
      return deserialize<_i18.VisitSyncResult>(data['data']);
    }
    if (dataClassName == 'AuditLog') {
      return deserialize<_i19.AuditLog>(data['data']);
    }
    if (dataClassName == 'ConsentLog') {
      return deserialize<_i20.ConsentLog>(data['data']);
    }
    if (dataClassName == 'EnrollmentToken') {
      return deserialize<_i21.EnrollmentToken>(data['data']);
    }
    if (dataClassName == 'AlertStatus') {
      return deserialize<_i22.AlertStatus>(data['data']);
    }
    if (dataClassName == 'ArrivalMethod') {
      return deserialize<_i23.ArrivalMethod>(data['data']);
    }
    if (dataClassName == 'ConsentPurpose') {
      return deserialize<_i24.ConsentPurpose>(data['data']);
    }
    if (dataClassName == 'RiskLevel') {
      return deserialize<_i25.RiskLevel>(data['data']);
    }
    if (dataClassName == 'SyncStatus') {
      return deserialize<_i26.SyncStatus>(data['data']);
    }
    if (dataClassName == 'UserRole') {
      return deserialize<_i27.UserRole>(data['data']);
    }
    if (dataClassName == 'AlertDispatchUnavailableException') {
      return deserialize<_i28.AlertDispatchUnavailableException>(data['data']);
    }
    if (dataClassName == 'AlertPermissionException') {
      return deserialize<_i29.AlertPermissionException>(data['data']);
    }
    if (dataClassName == 'AlertValidationException') {
      return deserialize<_i30.AlertValidationException>(data['data']);
    }
    if (dataClassName == 'AuthenticationFailedException') {
      return deserialize<_i31.AuthenticationFailedException>(data['data']);
    }
    if (dataClassName == 'EndpointDisabledException') {
      return deserialize<_i32.EndpointDisabledException>(data['data']);
    }
    if (dataClassName == 'EnrollmentException') {
      return deserialize<_i33.EnrollmentException>(data['data']);
    }
    if (dataClassName == 'OtpRequestException') {
      return deserialize<_i34.OtpRequestException>(data['data']);
    }
    if (dataClassName == 'MicroArea') {
      return deserialize<_i35.MicroArea>(data['data']);
    }
    if (dataClassName == 'OtpChallenge') {
      return deserialize<_i36.OtpChallenge>(data['data']);
    }
    if (dataClassName == 'Patient') {
      return deserialize<_i37.Patient>(data['data']);
    }
    if (dataClassName == 'TriageAnswer') {
      return deserialize<_i38.TriageAnswer>(data['data']);
    }
    if (dataClassName == 'TriageSession') {
      return deserialize<_i39.TriageSession>(data['data']);
    }
    if (dataClassName == 'Ubs') {
      return deserialize<_i40.Ubs>(data['data']);
    }
    if (dataClassName == 'User') {
      return deserialize<_i41.User>(data['data']);
    }
    if (dataClassName == 'UserCredential') {
      return deserialize<_i42.UserCredential>(data['data']);
    }
    if (dataClassName == 'Visit') {
      return deserialize<_i43.Visit>(data['data']);
    }
    if (dataClassName.startsWith('serverpod.')) {
      data['className'] = dataClassName.substring(10);
      return _i2.Protocol().deserializeByClassName(data);
    }
    return super.deserializeByClassName(data);
  }

  @override
  _i1.Table? getTableForType(Type t) {
    {
      var table = _i2.Protocol().getTableForType(t);
      if (table != null) {
        return table;
      }
    }
    switch (t) {
      case _i3.Acs:
        return _i3.Acs.t;
      case _i4.Alert:
        return _i4.Alert.t;
      case _i5.AlertDeliveryRecord:
        return _i5.AlertDeliveryRecord.t;
      case _i6.AlertIdempotencyKey:
        return _i6.AlertIdempotencyKey.t;
      case _i7.AlertOutboxEntry:
        return _i7.AlertOutboxEntry.t;
      case _i19.AuditLog:
        return _i19.AuditLog.t;
      case _i20.ConsentLog:
        return _i20.ConsentLog.t;
      case _i21.EnrollmentToken:
        return _i21.EnrollmentToken.t;
      case _i35.MicroArea:
        return _i35.MicroArea.t;
      case _i36.OtpChallenge:
        return _i36.OtpChallenge.t;
      case _i37.Patient:
        return _i37.Patient.t;
      case _i39.TriageSession:
        return _i39.TriageSession.t;
      case _i40.Ubs:
        return _i40.Ubs.t;
      case _i41.User:
        return _i41.User.t;
      case _i42.UserCredential:
        return _i42.UserCredential.t;
      case _i43.Visit:
        return _i43.Visit.t;
    }
    return null;
  }

  @override
  List<_i2.TableDefinition> getTargetTableDefinitions() =>
      targetTableDefinitions;

  @override
  String getModuleName() => 'sinalacs';

  /// Maps any `Record`s known to this [Protocol] to their JSON representation
  ///
  /// Throws in case the record type is not known.
  ///
  /// This method will return `null` (only) for `null` inputs.
  Map<String, dynamic>? mapRecordToJson(Record? record) {
    if (record == null) {
      return null;
    }
    try {
      return _i2.Protocol().mapRecordToJson(record);
    } catch (_) {}
    throw Exception('Unsupported record type ${record.runtimeType}');
  }
}
