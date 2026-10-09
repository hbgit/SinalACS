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
import 'acs_refresh_token.dart' as _i4;
import 'acs_upload_token.dart' as _i5;
import 'alert.dart' as _i6;
import 'alert_delivery_record.dart' as _i7;
import 'alert_idempotency_key.dart' as _i8;
import 'alert_outbox_entry.dart' as _i9;
import 'api/admin_acs.dart' as _i10;
import 'api/admin_acs_creation_result.dart' as _i11;
import 'api/admin_alert.dart' as _i12;
import 'api/admin_alert_page.dart' as _i13;
import 'api/admin_audit_entry.dart' as _i14;
import 'api/admin_audit_page.dart' as _i15;
import 'api/admin_data_subject_request.dart' as _i16;
import 'api/admin_data_subject_request_detail.dart' as _i17;
import 'api/admin_data_subject_request_page.dart' as _i18;
import 'api/admin_indicators.dart' as _i19;
import 'api/admin_micro_area.dart' as _i20;
import 'api/admin_password_reset_result.dart' as _i21;
import 'api/admin_staff.dart' as _i22;
import 'api/admin_staff_mfa_reset_result.dart' as _i23;
import 'api/alert_ack_result.dart' as _i24;
import 'api/alert_status_result.dart' as _i25;
import 'api/development_login_result.dart' as _i26;
import 'api/enrollment_result.dart' as _i27;
import 'api/enrollment_token_result.dart' as _i28;
import 'api/micro_area_patient.dart' as _i29;
import 'api/notice_send_result.dart' as _i30;
import 'api/patient_consent_record.dart' as _i31;
import 'api/patient_data_overview.dart' as _i32;
import 'api/patient_data_subject_request_record.dart' as _i33;
import 'api/patient_risk_event.dart' as _i34;
import 'api/red_alert_result.dart' as _i35;
import 'api/service_health.dart' as _i36;
import 'api/terms_change_notice.dart' as _i37;
import 'api/totp_enrollment_start.dart' as _i38;
import 'api/triage_result.dart' as _i39;
import 'api/ubs_contact.dart' as _i40;
import 'api/visit_sync_entry.dart' as _i41;
import 'api/visit_sync_result.dart' as _i42;
import 'audit_log.dart' as _i43;
import 'consent_log.dart' as _i44;
import 'data_subject_request.dart' as _i45;
import 'enrollment_token.dart' as _i46;
import 'enums/alert_status.dart' as _i47;
import 'enums/arrival_method.dart' as _i48;
import 'enums/consent_purpose.dart' as _i49;
import 'enums/data_subject_request_status.dart' as _i50;
import 'enums/data_subject_request_type.dart' as _i51;
import 'enums/risk_level.dart' as _i52;
import 'enums/sync_status.dart' as _i53;
import 'enums/user_role.dart' as _i54;
import 'enums/visit_authorship.dart' as _i55;
import 'exceptions/admin_invalid_request_exception.dart' as _i56;
import 'exceptions/alert_dispatch_unavailable_exception.dart' as _i57;
import 'exceptions/alert_permission_exception.dart' as _i58;
import 'exceptions/alert_validation_exception.dart' as _i59;
import 'exceptions/authentication_failed_exception.dart' as _i60;
import 'exceptions/data_rights_exception.dart' as _i61;
import 'exceptions/endpoint_disabled_exception.dart' as _i62;
import 'exceptions/enrollment_exception.dart' as _i63;
import 'exceptions/mfa_enrollment_required_exception.dart' as _i64;
import 'exceptions/mfa_required_exception.dart' as _i65;
import 'exceptions/notice_delivery_exception.dart' as _i66;
import 'exceptions/otp_request_exception.dart' as _i67;
import 'exceptions/session_expired_exception.dart' as _i68;
import 'micro_area.dart' as _i69;
import 'otp_challenge.dart' as _i70;
import 'patient.dart' as _i71;
import 'push_token.dart' as _i72;
import 'staff_account.dart' as _i73;
import 'triage_answer.dart' as _i74;
import 'triage_session.dart' as _i75;
import 'ubs.dart' as _i76;
import 'user.dart' as _i77;
import 'user_credential.dart' as _i78;
import 'visit.dart' as _i79;
import 'package:sinalacs_server/src/generated/api/admin_micro_area.dart'
    as _i80;
import 'package:sinalacs_server/src/generated/api/admin_acs.dart' as _i81;
import 'package:sinalacs_server/src/generated/api/admin_staff.dart' as _i82;
import 'package:sinalacs_server/src/generated/api/micro_area_patient.dart'
    as _i83;
import 'package:sinalacs_server/src/generated/api/visit_sync_result.dart'
    as _i84;
import 'package:sinalacs_server/src/generated/api/visit_sync_entry.dart'
    as _i85;
export 'acs.dart';
export 'acs_refresh_token.dart';
export 'acs_upload_token.dart';
export 'alert.dart';
export 'alert_delivery_record.dart';
export 'alert_idempotency_key.dart';
export 'alert_outbox_entry.dart';
export 'api/admin_acs.dart';
export 'api/admin_acs_creation_result.dart';
export 'api/admin_alert.dart';
export 'api/admin_alert_page.dart';
export 'api/admin_audit_entry.dart';
export 'api/admin_audit_page.dart';
export 'api/admin_data_subject_request.dart';
export 'api/admin_data_subject_request_detail.dart';
export 'api/admin_data_subject_request_page.dart';
export 'api/admin_indicators.dart';
export 'api/admin_micro_area.dart';
export 'api/admin_password_reset_result.dart';
export 'api/admin_staff.dart';
export 'api/admin_staff_mfa_reset_result.dart';
export 'api/alert_ack_result.dart';
export 'api/alert_status_result.dart';
export 'api/development_login_result.dart';
export 'api/enrollment_result.dart';
export 'api/enrollment_token_result.dart';
export 'api/micro_area_patient.dart';
export 'api/notice_send_result.dart';
export 'api/patient_consent_record.dart';
export 'api/patient_data_overview.dart';
export 'api/patient_data_subject_request_record.dart';
export 'api/patient_risk_event.dart';
export 'api/red_alert_result.dart';
export 'api/service_health.dart';
export 'api/terms_change_notice.dart';
export 'api/totp_enrollment_start.dart';
export 'api/triage_result.dart';
export 'api/ubs_contact.dart';
export 'api/visit_sync_entry.dart';
export 'api/visit_sync_result.dart';
export 'audit_log.dart';
export 'consent_log.dart';
export 'data_subject_request.dart';
export 'enrollment_token.dart';
export 'enums/alert_status.dart';
export 'enums/arrival_method.dart';
export 'enums/consent_purpose.dart';
export 'enums/data_subject_request_status.dart';
export 'enums/data_subject_request_type.dart';
export 'enums/risk_level.dart';
export 'enums/sync_status.dart';
export 'enums/user_role.dart';
export 'enums/visit_authorship.dart';
export 'exceptions/admin_invalid_request_exception.dart';
export 'exceptions/alert_dispatch_unavailable_exception.dart';
export 'exceptions/alert_permission_exception.dart';
export 'exceptions/alert_validation_exception.dart';
export 'exceptions/authentication_failed_exception.dart';
export 'exceptions/data_rights_exception.dart';
export 'exceptions/endpoint_disabled_exception.dart';
export 'exceptions/enrollment_exception.dart';
export 'exceptions/mfa_enrollment_required_exception.dart';
export 'exceptions/mfa_required_exception.dart';
export 'exceptions/notice_delivery_exception.dart';
export 'exceptions/otp_request_exception.dart';
export 'exceptions/session_expired_exception.dart';
export 'micro_area.dart';
export 'otp_challenge.dart';
export 'patient.dart';
export 'push_token.dart';
export 'staff_account.dart';
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
      name: 'acs_refresh_tokens',
      dartName: 'AcsRefreshToken',
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
          name: 'familyId',
          columnType: _i2.ColumnType.uuid,
          isNullable: false,
          dartType: 'UuidValue',
        ),
        _i2.ColumnDefinition(
          name: 'tokenHash',
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
          name: 'issuedAt',
          columnType: _i2.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
        ),
        _i2.ColumnDefinition(
          name: 'idleExpiresAt',
          columnType: _i2.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
        ),
        _i2.ColumnDefinition(
          name: 'absoluteExpiresAt',
          columnType: _i2.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
        ),
        _i2.ColumnDefinition(
          name: 'rotatedAt',
          columnType: _i2.ColumnType.timestampWithoutTimeZone,
          isNullable: true,
          dartType: 'DateTime?',
        ),
        _i2.ColumnDefinition(
          name: 'revokedAt',
          columnType: _i2.ColumnType.timestampWithoutTimeZone,
          isNullable: true,
          dartType: 'DateTime?',
        ),
      ],
      foreignKeys: [
        _i2.ForeignKeyDefinition(
          constraintName: 'acs_refresh_tokens_fk_0',
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
          indexName: 'acs_refresh_tokens_pkey',
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
          indexName: 'acs_refresh_tokens_hash_key',
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
        _i2.IndexDefinition(
          indexName: 'acs_refresh_tokens_family_idx',
          tableSpace: null,
          elements: [
            _i2.IndexElementDefinition(
              type: _i2.IndexElementDefinitionType.column,
              definition: 'familyId',
            ),
          ],
          type: 'btree',
          isUnique: false,
          isPrimary: false,
        ),
        _i2.IndexDefinition(
          indexName: 'acs_refresh_tokens_user_idx',
          tableSpace: null,
          elements: [
            _i2.IndexElementDefinition(
              type: _i2.IndexElementDefinitionType.column,
              definition: 'userId',
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
      name: 'acs_upload_tokens',
      dartName: 'AcsUploadToken',
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
          name: 'tokenHash',
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
          name: 'issuedAt',
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
          name: 'revokedAt',
          columnType: _i2.ColumnType.timestampWithoutTimeZone,
          isNullable: true,
          dartType: 'DateTime?',
        ),
      ],
      foreignKeys: [
        _i2.ForeignKeyDefinition(
          constraintName: 'acs_upload_tokens_fk_0',
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
          indexName: 'acs_upload_tokens_pkey',
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
          indexName: 'acs_upload_tokens_hash_key',
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
        _i2.IndexDefinition(
          indexName: 'acs_upload_tokens_user_device_idx',
          tableSpace: null,
          elements: [
            _i2.IndexElementDefinition(
              type: _i2.IndexElementDefinitionType.column,
              definition: 'userId',
            ),
            _i2.IndexElementDefinition(
              type: _i2.IndexElementDefinitionType.column,
              definition: 'deviceId',
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
      name: 'data_subject_requests',
      dartName: 'DataSubjectRequest',
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
          name: 'requestType',
          columnType: _i2.ColumnType.text,
          isNullable: false,
          dartType: 'protocol:DataSubjectRequestType',
        ),
        _i2.ColumnDefinition(
          name: 'detailsEncrypted',
          columnType: _i2.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _i2.ColumnDefinition(
          name: 'detailsKeyVersion',
          columnType: _i2.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _i2.ColumnDefinition(
          name: 'status',
          columnType: _i2.ColumnType.text,
          isNullable: false,
          dartType: 'protocol:DataSubjectRequestStatus',
        ),
        _i2.ColumnDefinition(
          name: 'createdAt',
          columnType: _i2.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
        ),
        _i2.ColumnDefinition(
          name: 'dueAt',
          columnType: _i2.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
        ),
        _i2.ColumnDefinition(
          name: 'decidedAt',
          columnType: _i2.ColumnType.timestampWithoutTimeZone,
          isNullable: true,
          dartType: 'DateTime?',
        ),
        _i2.ColumnDefinition(
          name: 'decidedBy',
          columnType: _i2.ColumnType.uuid,
          isNullable: true,
          dartType: 'UuidValue?',
        ),
        _i2.ColumnDefinition(
          name: 'resolutionEncrypted',
          columnType: _i2.ColumnType.text,
          isNullable: true,
          dartType: 'String?',
        ),
        _i2.ColumnDefinition(
          name: 'resolutionKeyVersion',
          columnType: _i2.ColumnType.bigint,
          isNullable: true,
          dartType: 'int?',
        ),
      ],
      foreignKeys: [
        _i2.ForeignKeyDefinition(
          constraintName: 'data_subject_requests_fk_0',
          columns: ['userId'],
          referenceTable: 'users',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _i2.ForeignKeyAction.noAction,
          onDelete: _i2.ForeignKeyAction.noAction,
          matchType: null,
        ),
        _i2.ForeignKeyDefinition(
          constraintName: 'data_subject_requests_fk_1',
          columns: ['decidedBy'],
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
          indexName: 'data_subject_requests_pkey',
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
          indexName: 'data_subject_requests_user_id_type_idx',
          tableSpace: null,
          elements: [
            _i2.IndexElementDefinition(
              type: _i2.IndexElementDefinitionType.column,
              definition: 'userId',
            ),
            _i2.IndexElementDefinition(
              type: _i2.IndexElementDefinitionType.column,
              definition: 'requestType',
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
      name: 'push_tokens',
      dartName: 'PushToken',
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
          name: 'microAreaId',
          columnType: _i2.ColumnType.uuid,
          isNullable: true,
          dartType: 'UuidValue?',
        ),
        _i2.ColumnDefinition(
          name: 'token',
          columnType: _i2.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _i2.ColumnDefinition(
          name: 'platform',
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
          name: 'updatedAt',
          columnType: _i2.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
        ),
      ],
      foreignKeys: [
        _i2.ForeignKeyDefinition(
          constraintName: 'push_tokens_fk_0',
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
          indexName: 'push_tokens_pkey',
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
          indexName: 'push_tokens_token_key',
          tableSpace: null,
          elements: [
            _i2.IndexElementDefinition(
              type: _i2.IndexElementDefinitionType.column,
              definition: 'token',
            ),
          ],
          type: 'btree',
          isUnique: true,
          isPrimary: false,
        ),
        _i2.IndexDefinition(
          indexName: 'push_tokens_user_id_idx',
          tableSpace: null,
          elements: [
            _i2.IndexElementDefinition(
              type: _i2.IndexElementDefinitionType.column,
              definition: 'userId',
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
      name: 'staff_accounts',
      dartName: 'StaffAccount',
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
          name: 'active',
          columnType: _i2.ColumnType.boolean,
          isNullable: false,
          dartType: 'bool',
        ),
        _i2.ColumnDefinition(
          name: 'ubsId',
          columnType: _i2.ColumnType.uuid,
          isNullable: true,
          dartType: 'UuidValue?',
        ),
        _i2.ColumnDefinition(
          name: 'activationCodeHash',
          columnType: _i2.ColumnType.text,
          isNullable: true,
          dartType: 'String?',
        ),
        _i2.ColumnDefinition(
          name: 'activationCodeExpiresAt',
          columnType: _i2.ColumnType.timestampWithoutTimeZone,
          isNullable: true,
          dartType: 'DateTime?',
        ),
        _i2.ColumnDefinition(
          name: 'activationCodeIssuedBy',
          columnType: _i2.ColumnType.text,
          isNullable: true,
          dartType: 'String?',
        ),
        _i2.ColumnDefinition(
          name: 'activationCodeIssuedAt',
          columnType: _i2.ColumnType.timestampWithoutTimeZone,
          isNullable: true,
          dartType: 'DateTime?',
        ),
      ],
      foreignKeys: [],
      indexes: [
        _i2.IndexDefinition(
          indexName: 'staff_accounts_pkey',
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
          indexName: 'staff_accounts_enrollment_id_key',
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
        _i2.ColumnDefinition(
          name: 'contactPhone',
          columnType: _i2.ColumnType.text,
          isNullable: true,
          dartType: 'String?',
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
          name: 'lockStreak',
          columnType: _i2.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
          columnDefault: '0',
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
        _i2.ColumnDefinition(
          name: 'totpSecretEncrypted',
          columnType: _i2.ColumnType.text,
          isNullable: true,
          dartType: 'String?',
        ),
        _i2.ColumnDefinition(
          name: 'totpKeyVersion',
          columnType: _i2.ColumnType.bigint,
          isNullable: true,
          dartType: 'int?',
        ),
        _i2.ColumnDefinition(
          name: 'totpEnabledAt',
          columnType: _i2.ColumnType.timestampWithoutTimeZone,
          isNullable: true,
          dartType: 'DateTime?',
        ),
        _i2.ColumnDefinition(
          name: 'totpLastStep',
          columnType: _i2.ColumnType.bigint,
          isNullable: true,
          dartType: 'int?',
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
          isNullable: true,
          dartType: 'UuidValue?',
        ),
        _i2.ColumnDefinition(
          name: 'authorship',
          columnType: _i2.ColumnType.text,
          isNullable: false,
          dartType: 'protocol:VisitAuthorship',
          columnDefault: '\'acs\'::text',
        ),
        _i2.ColumnDefinition(
          name: 'originDeviceId',
          columnType: _i2.ColumnType.text,
          isNullable: true,
          dartType: 'String?',
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
    if (t == _i4.AcsRefreshToken) {
      return _i4.AcsRefreshToken.fromJson(data) as T;
    }
    if (t == _i5.AcsUploadToken) {
      return _i5.AcsUploadToken.fromJson(data) as T;
    }
    if (t == _i6.Alert) {
      return _i6.Alert.fromJson(data) as T;
    }
    if (t == _i7.AlertDeliveryRecord) {
      return _i7.AlertDeliveryRecord.fromJson(data) as T;
    }
    if (t == _i8.AlertIdempotencyKey) {
      return _i8.AlertIdempotencyKey.fromJson(data) as T;
    }
    if (t == _i9.AlertOutboxEntry) {
      return _i9.AlertOutboxEntry.fromJson(data) as T;
    }
    if (t == _i10.AdminAcs) {
      return _i10.AdminAcs.fromJson(data) as T;
    }
    if (t == _i11.AdminAcsCreationResult) {
      return _i11.AdminAcsCreationResult.fromJson(data) as T;
    }
    if (t == _i12.AdminAlert) {
      return _i12.AdminAlert.fromJson(data) as T;
    }
    if (t == _i13.AdminAlertPage) {
      return _i13.AdminAlertPage.fromJson(data) as T;
    }
    if (t == _i14.AdminAuditEntry) {
      return _i14.AdminAuditEntry.fromJson(data) as T;
    }
    if (t == _i15.AdminAuditPage) {
      return _i15.AdminAuditPage.fromJson(data) as T;
    }
    if (t == _i16.AdminDataSubjectRequest) {
      return _i16.AdminDataSubjectRequest.fromJson(data) as T;
    }
    if (t == _i17.AdminDataSubjectRequestDetail) {
      return _i17.AdminDataSubjectRequestDetail.fromJson(data) as T;
    }
    if (t == _i18.AdminDataSubjectRequestPage) {
      return _i18.AdminDataSubjectRequestPage.fromJson(data) as T;
    }
    if (t == _i19.AdminIndicators) {
      return _i19.AdminIndicators.fromJson(data) as T;
    }
    if (t == _i20.AdminMicroArea) {
      return _i20.AdminMicroArea.fromJson(data) as T;
    }
    if (t == _i21.AdminPasswordResetResult) {
      return _i21.AdminPasswordResetResult.fromJson(data) as T;
    }
    if (t == _i22.AdminStaff) {
      return _i22.AdminStaff.fromJson(data) as T;
    }
    if (t == _i23.AdminStaffMfaResetResult) {
      return _i23.AdminStaffMfaResetResult.fromJson(data) as T;
    }
    if (t == _i24.AlertAckResult) {
      return _i24.AlertAckResult.fromJson(data) as T;
    }
    if (t == _i25.AlertStatusResult) {
      return _i25.AlertStatusResult.fromJson(data) as T;
    }
    if (t == _i26.DevelopmentLoginResult) {
      return _i26.DevelopmentLoginResult.fromJson(data) as T;
    }
    if (t == _i27.EnrollmentResult) {
      return _i27.EnrollmentResult.fromJson(data) as T;
    }
    if (t == _i28.EnrollmentTokenResult) {
      return _i28.EnrollmentTokenResult.fromJson(data) as T;
    }
    if (t == _i29.MicroAreaPatient) {
      return _i29.MicroAreaPatient.fromJson(data) as T;
    }
    if (t == _i30.NoticeSendResult) {
      return _i30.NoticeSendResult.fromJson(data) as T;
    }
    if (t == _i31.PatientConsentRecord) {
      return _i31.PatientConsentRecord.fromJson(data) as T;
    }
    if (t == _i32.PatientDataOverview) {
      return _i32.PatientDataOverview.fromJson(data) as T;
    }
    if (t == _i33.PatientDataSubjectRequestRecord) {
      return _i33.PatientDataSubjectRequestRecord.fromJson(data) as T;
    }
    if (t == _i34.PatientRiskEvent) {
      return _i34.PatientRiskEvent.fromJson(data) as T;
    }
    if (t == _i35.RedAlertResult) {
      return _i35.RedAlertResult.fromJson(data) as T;
    }
    if (t == _i36.ServiceHealth) {
      return _i36.ServiceHealth.fromJson(data) as T;
    }
    if (t == _i37.TermsChangeNotice) {
      return _i37.TermsChangeNotice.fromJson(data) as T;
    }
    if (t == _i38.TotpEnrollmentStart) {
      return _i38.TotpEnrollmentStart.fromJson(data) as T;
    }
    if (t == _i39.TriageResult) {
      return _i39.TriageResult.fromJson(data) as T;
    }
    if (t == _i40.UbsContact) {
      return _i40.UbsContact.fromJson(data) as T;
    }
    if (t == _i41.VisitSyncEntry) {
      return _i41.VisitSyncEntry.fromJson(data) as T;
    }
    if (t == _i42.VisitSyncResult) {
      return _i42.VisitSyncResult.fromJson(data) as T;
    }
    if (t == _i43.AuditLog) {
      return _i43.AuditLog.fromJson(data) as T;
    }
    if (t == _i44.ConsentLog) {
      return _i44.ConsentLog.fromJson(data) as T;
    }
    if (t == _i45.DataSubjectRequest) {
      return _i45.DataSubjectRequest.fromJson(data) as T;
    }
    if (t == _i46.EnrollmentToken) {
      return _i46.EnrollmentToken.fromJson(data) as T;
    }
    if (t == _i47.AlertStatus) {
      return _i47.AlertStatus.fromJson(data) as T;
    }
    if (t == _i48.ArrivalMethod) {
      return _i48.ArrivalMethod.fromJson(data) as T;
    }
    if (t == _i49.ConsentPurpose) {
      return _i49.ConsentPurpose.fromJson(data) as T;
    }
    if (t == _i50.DataSubjectRequestStatus) {
      return _i50.DataSubjectRequestStatus.fromJson(data) as T;
    }
    if (t == _i51.DataSubjectRequestType) {
      return _i51.DataSubjectRequestType.fromJson(data) as T;
    }
    if (t == _i52.RiskLevel) {
      return _i52.RiskLevel.fromJson(data) as T;
    }
    if (t == _i53.SyncStatus) {
      return _i53.SyncStatus.fromJson(data) as T;
    }
    if (t == _i54.UserRole) {
      return _i54.UserRole.fromJson(data) as T;
    }
    if (t == _i55.VisitAuthorship) {
      return _i55.VisitAuthorship.fromJson(data) as T;
    }
    if (t == _i56.AdminInvalidRequestException) {
      return _i56.AdminInvalidRequestException.fromJson(data) as T;
    }
    if (t == _i57.AlertDispatchUnavailableException) {
      return _i57.AlertDispatchUnavailableException.fromJson(data) as T;
    }
    if (t == _i58.AlertPermissionException) {
      return _i58.AlertPermissionException.fromJson(data) as T;
    }
    if (t == _i59.AlertValidationException) {
      return _i59.AlertValidationException.fromJson(data) as T;
    }
    if (t == _i60.AuthenticationFailedException) {
      return _i60.AuthenticationFailedException.fromJson(data) as T;
    }
    if (t == _i61.DataRightsException) {
      return _i61.DataRightsException.fromJson(data) as T;
    }
    if (t == _i62.EndpointDisabledException) {
      return _i62.EndpointDisabledException.fromJson(data) as T;
    }
    if (t == _i63.EnrollmentException) {
      return _i63.EnrollmentException.fromJson(data) as T;
    }
    if (t == _i64.MfaEnrollmentRequiredException) {
      return _i64.MfaEnrollmentRequiredException.fromJson(data) as T;
    }
    if (t == _i65.MfaRequiredException) {
      return _i65.MfaRequiredException.fromJson(data) as T;
    }
    if (t == _i66.NoticeDeliveryException) {
      return _i66.NoticeDeliveryException.fromJson(data) as T;
    }
    if (t == _i67.OtpRequestException) {
      return _i67.OtpRequestException.fromJson(data) as T;
    }
    if (t == _i68.SessionExpiredException) {
      return _i68.SessionExpiredException.fromJson(data) as T;
    }
    if (t == _i69.MicroArea) {
      return _i69.MicroArea.fromJson(data) as T;
    }
    if (t == _i70.OtpChallenge) {
      return _i70.OtpChallenge.fromJson(data) as T;
    }
    if (t == _i71.Patient) {
      return _i71.Patient.fromJson(data) as T;
    }
    if (t == _i72.PushToken) {
      return _i72.PushToken.fromJson(data) as T;
    }
    if (t == _i73.StaffAccount) {
      return _i73.StaffAccount.fromJson(data) as T;
    }
    if (t == _i74.TriageAnswer) {
      return _i74.TriageAnswer.fromJson(data) as T;
    }
    if (t == _i75.TriageSession) {
      return _i75.TriageSession.fromJson(data) as T;
    }
    if (t == _i76.Ubs) {
      return _i76.Ubs.fromJson(data) as T;
    }
    if (t == _i77.User) {
      return _i77.User.fromJson(data) as T;
    }
    if (t == _i78.UserCredential) {
      return _i78.UserCredential.fromJson(data) as T;
    }
    if (t == _i79.Visit) {
      return _i79.Visit.fromJson(data) as T;
    }
    if (t == _i1.getType<_i3.Acs?>()) {
      return (data != null ? _i3.Acs.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i4.AcsRefreshToken?>()) {
      return (data != null ? _i4.AcsRefreshToken.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i5.AcsUploadToken?>()) {
      return (data != null ? _i5.AcsUploadToken.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i6.Alert?>()) {
      return (data != null ? _i6.Alert.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i7.AlertDeliveryRecord?>()) {
      return (data != null ? _i7.AlertDeliveryRecord.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i8.AlertIdempotencyKey?>()) {
      return (data != null ? _i8.AlertIdempotencyKey.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i9.AlertOutboxEntry?>()) {
      return (data != null ? _i9.AlertOutboxEntry.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i10.AdminAcs?>()) {
      return (data != null ? _i10.AdminAcs.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i11.AdminAcsCreationResult?>()) {
      return (data != null ? _i11.AdminAcsCreationResult.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i12.AdminAlert?>()) {
      return (data != null ? _i12.AdminAlert.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i13.AdminAlertPage?>()) {
      return (data != null ? _i13.AdminAlertPage.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i14.AdminAuditEntry?>()) {
      return (data != null ? _i14.AdminAuditEntry.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i15.AdminAuditPage?>()) {
      return (data != null ? _i15.AdminAuditPage.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i16.AdminDataSubjectRequest?>()) {
      return (data != null ? _i16.AdminDataSubjectRequest.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i17.AdminDataSubjectRequestDetail?>()) {
      return (data != null
              ? _i17.AdminDataSubjectRequestDetail.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i18.AdminDataSubjectRequestPage?>()) {
      return (data != null
              ? _i18.AdminDataSubjectRequestPage.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i19.AdminIndicators?>()) {
      return (data != null ? _i19.AdminIndicators.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i20.AdminMicroArea?>()) {
      return (data != null ? _i20.AdminMicroArea.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i21.AdminPasswordResetResult?>()) {
      return (data != null
              ? _i21.AdminPasswordResetResult.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i22.AdminStaff?>()) {
      return (data != null ? _i22.AdminStaff.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i23.AdminStaffMfaResetResult?>()) {
      return (data != null
              ? _i23.AdminStaffMfaResetResult.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i24.AlertAckResult?>()) {
      return (data != null ? _i24.AlertAckResult.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i25.AlertStatusResult?>()) {
      return (data != null ? _i25.AlertStatusResult.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i26.DevelopmentLoginResult?>()) {
      return (data != null ? _i26.DevelopmentLoginResult.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i27.EnrollmentResult?>()) {
      return (data != null ? _i27.EnrollmentResult.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i28.EnrollmentTokenResult?>()) {
      return (data != null ? _i28.EnrollmentTokenResult.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i29.MicroAreaPatient?>()) {
      return (data != null ? _i29.MicroAreaPatient.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i30.NoticeSendResult?>()) {
      return (data != null ? _i30.NoticeSendResult.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i31.PatientConsentRecord?>()) {
      return (data != null ? _i31.PatientConsentRecord.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i32.PatientDataOverview?>()) {
      return (data != null ? _i32.PatientDataOverview.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i33.PatientDataSubjectRequestRecord?>()) {
      return (data != null
              ? _i33.PatientDataSubjectRequestRecord.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i34.PatientRiskEvent?>()) {
      return (data != null ? _i34.PatientRiskEvent.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i35.RedAlertResult?>()) {
      return (data != null ? _i35.RedAlertResult.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i36.ServiceHealth?>()) {
      return (data != null ? _i36.ServiceHealth.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i37.TermsChangeNotice?>()) {
      return (data != null ? _i37.TermsChangeNotice.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i38.TotpEnrollmentStart?>()) {
      return (data != null ? _i38.TotpEnrollmentStart.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i39.TriageResult?>()) {
      return (data != null ? _i39.TriageResult.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i40.UbsContact?>()) {
      return (data != null ? _i40.UbsContact.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i41.VisitSyncEntry?>()) {
      return (data != null ? _i41.VisitSyncEntry.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i42.VisitSyncResult?>()) {
      return (data != null ? _i42.VisitSyncResult.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i43.AuditLog?>()) {
      return (data != null ? _i43.AuditLog.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i44.ConsentLog?>()) {
      return (data != null ? _i44.ConsentLog.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i45.DataSubjectRequest?>()) {
      return (data != null ? _i45.DataSubjectRequest.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i46.EnrollmentToken?>()) {
      return (data != null ? _i46.EnrollmentToken.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i47.AlertStatus?>()) {
      return (data != null ? _i47.AlertStatus.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i48.ArrivalMethod?>()) {
      return (data != null ? _i48.ArrivalMethod.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i49.ConsentPurpose?>()) {
      return (data != null ? _i49.ConsentPurpose.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i50.DataSubjectRequestStatus?>()) {
      return (data != null
              ? _i50.DataSubjectRequestStatus.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i51.DataSubjectRequestType?>()) {
      return (data != null ? _i51.DataSubjectRequestType.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i52.RiskLevel?>()) {
      return (data != null ? _i52.RiskLevel.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i53.SyncStatus?>()) {
      return (data != null ? _i53.SyncStatus.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i54.UserRole?>()) {
      return (data != null ? _i54.UserRole.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i55.VisitAuthorship?>()) {
      return (data != null ? _i55.VisitAuthorship.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i56.AdminInvalidRequestException?>()) {
      return (data != null
              ? _i56.AdminInvalidRequestException.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i57.AlertDispatchUnavailableException?>()) {
      return (data != null
              ? _i57.AlertDispatchUnavailableException.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i58.AlertPermissionException?>()) {
      return (data != null
              ? _i58.AlertPermissionException.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i59.AlertValidationException?>()) {
      return (data != null
              ? _i59.AlertValidationException.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i60.AuthenticationFailedException?>()) {
      return (data != null
              ? _i60.AuthenticationFailedException.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i61.DataRightsException?>()) {
      return (data != null ? _i61.DataRightsException.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i62.EndpointDisabledException?>()) {
      return (data != null
              ? _i62.EndpointDisabledException.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i63.EnrollmentException?>()) {
      return (data != null ? _i63.EnrollmentException.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i64.MfaEnrollmentRequiredException?>()) {
      return (data != null
              ? _i64.MfaEnrollmentRequiredException.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i65.MfaRequiredException?>()) {
      return (data != null ? _i65.MfaRequiredException.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i66.NoticeDeliveryException?>()) {
      return (data != null ? _i66.NoticeDeliveryException.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i67.OtpRequestException?>()) {
      return (data != null ? _i67.OtpRequestException.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i68.SessionExpiredException?>()) {
      return (data != null ? _i68.SessionExpiredException.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i69.MicroArea?>()) {
      return (data != null ? _i69.MicroArea.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i70.OtpChallenge?>()) {
      return (data != null ? _i70.OtpChallenge.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i71.Patient?>()) {
      return (data != null ? _i71.Patient.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i72.PushToken?>()) {
      return (data != null ? _i72.PushToken.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i73.StaffAccount?>()) {
      return (data != null ? _i73.StaffAccount.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i74.TriageAnswer?>()) {
      return (data != null ? _i74.TriageAnswer.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i75.TriageSession?>()) {
      return (data != null ? _i75.TriageSession.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i76.Ubs?>()) {
      return (data != null ? _i76.Ubs.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i77.User?>()) {
      return (data != null ? _i77.User.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i78.UserCredential?>()) {
      return (data != null ? _i78.UserCredential.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i79.Visit?>()) {
      return (data != null ? _i79.Visit.fromJson(data) : null) as T;
    }
    if (t == List<_i12.AdminAlert>) {
      return (data as List).map((e) => deserialize<_i12.AdminAlert>(e)).toList()
          as T;
    }
    if (t == List<_i14.AdminAuditEntry>) {
      return (data as List)
              .map((e) => deserialize<_i14.AdminAuditEntry>(e))
              .toList()
          as T;
    }
    if (t == List<_i16.AdminDataSubjectRequest>) {
      return (data as List)
              .map((e) => deserialize<_i16.AdminDataSubjectRequest>(e))
              .toList()
          as T;
    }
    if (t == List<String>) {
      return (data as List).map((e) => deserialize<String>(e)).toList() as T;
    }
    if (t == List<_i31.PatientConsentRecord>) {
      return (data as List)
              .map((e) => deserialize<_i31.PatientConsentRecord>(e))
              .toList()
          as T;
    }
    if (t == List<_i34.PatientRiskEvent>) {
      return (data as List)
              .map((e) => deserialize<_i34.PatientRiskEvent>(e))
              .toList()
          as T;
    }
    if (t == List<_i33.PatientDataSubjectRequestRecord>) {
      return (data as List)
              .map((e) => deserialize<_i33.PatientDataSubjectRequestRecord>(e))
              .toList()
          as T;
    }
    if (t == Map<String, String>) {
      return (data as Map).map(
            (k, v) => MapEntry(deserialize<String>(k), deserialize<String>(v)),
          )
          as T;
    }
    if (t == List<_i80.AdminMicroArea>) {
      return (data as List)
              .map((e) => deserialize<_i80.AdminMicroArea>(e))
              .toList()
          as T;
    }
    if (t == List<_i81.AdminAcs>) {
      return (data as List).map((e) => deserialize<_i81.AdminAcs>(e)).toList()
          as T;
    }
    if (t == List<_i82.AdminStaff>) {
      return (data as List).map((e) => deserialize<_i82.AdminStaff>(e)).toList()
          as T;
    }
    if (t == List<_i83.MicroAreaPatient>) {
      return (data as List)
              .map((e) => deserialize<_i83.MicroAreaPatient>(e))
              .toList()
          as T;
    }
    if (t == List<String>) {
      return (data as List).map((e) => deserialize<String>(e)).toList() as T;
    }
    if (t == List<_i84.VisitSyncResult>) {
      return (data as List)
              .map((e) => deserialize<_i84.VisitSyncResult>(e))
              .toList()
          as T;
    }
    if (t == List<_i85.VisitSyncEntry>) {
      return (data as List)
              .map((e) => deserialize<_i85.VisitSyncEntry>(e))
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
      _i4.AcsRefreshToken => 'AcsRefreshToken',
      _i5.AcsUploadToken => 'AcsUploadToken',
      _i6.Alert => 'Alert',
      _i7.AlertDeliveryRecord => 'AlertDeliveryRecord',
      _i8.AlertIdempotencyKey => 'AlertIdempotencyKey',
      _i9.AlertOutboxEntry => 'AlertOutboxEntry',
      _i10.AdminAcs => 'AdminAcs',
      _i11.AdminAcsCreationResult => 'AdminAcsCreationResult',
      _i12.AdminAlert => 'AdminAlert',
      _i13.AdminAlertPage => 'AdminAlertPage',
      _i14.AdminAuditEntry => 'AdminAuditEntry',
      _i15.AdminAuditPage => 'AdminAuditPage',
      _i16.AdminDataSubjectRequest => 'AdminDataSubjectRequest',
      _i17.AdminDataSubjectRequestDetail => 'AdminDataSubjectRequestDetail',
      _i18.AdminDataSubjectRequestPage => 'AdminDataSubjectRequestPage',
      _i19.AdminIndicators => 'AdminIndicators',
      _i20.AdminMicroArea => 'AdminMicroArea',
      _i21.AdminPasswordResetResult => 'AdminPasswordResetResult',
      _i22.AdminStaff => 'AdminStaff',
      _i23.AdminStaffMfaResetResult => 'AdminStaffMfaResetResult',
      _i24.AlertAckResult => 'AlertAckResult',
      _i25.AlertStatusResult => 'AlertStatusResult',
      _i26.DevelopmentLoginResult => 'DevelopmentLoginResult',
      _i27.EnrollmentResult => 'EnrollmentResult',
      _i28.EnrollmentTokenResult => 'EnrollmentTokenResult',
      _i29.MicroAreaPatient => 'MicroAreaPatient',
      _i30.NoticeSendResult => 'NoticeSendResult',
      _i31.PatientConsentRecord => 'PatientConsentRecord',
      _i32.PatientDataOverview => 'PatientDataOverview',
      _i33.PatientDataSubjectRequestRecord => 'PatientDataSubjectRequestRecord',
      _i34.PatientRiskEvent => 'PatientRiskEvent',
      _i35.RedAlertResult => 'RedAlertResult',
      _i36.ServiceHealth => 'ServiceHealth',
      _i37.TermsChangeNotice => 'TermsChangeNotice',
      _i38.TotpEnrollmentStart => 'TotpEnrollmentStart',
      _i39.TriageResult => 'TriageResult',
      _i40.UbsContact => 'UbsContact',
      _i41.VisitSyncEntry => 'VisitSyncEntry',
      _i42.VisitSyncResult => 'VisitSyncResult',
      _i43.AuditLog => 'AuditLog',
      _i44.ConsentLog => 'ConsentLog',
      _i45.DataSubjectRequest => 'DataSubjectRequest',
      _i46.EnrollmentToken => 'EnrollmentToken',
      _i47.AlertStatus => 'AlertStatus',
      _i48.ArrivalMethod => 'ArrivalMethod',
      _i49.ConsentPurpose => 'ConsentPurpose',
      _i50.DataSubjectRequestStatus => 'DataSubjectRequestStatus',
      _i51.DataSubjectRequestType => 'DataSubjectRequestType',
      _i52.RiskLevel => 'RiskLevel',
      _i53.SyncStatus => 'SyncStatus',
      _i54.UserRole => 'UserRole',
      _i55.VisitAuthorship => 'VisitAuthorship',
      _i56.AdminInvalidRequestException => 'AdminInvalidRequestException',
      _i57.AlertDispatchUnavailableException =>
        'AlertDispatchUnavailableException',
      _i58.AlertPermissionException => 'AlertPermissionException',
      _i59.AlertValidationException => 'AlertValidationException',
      _i60.AuthenticationFailedException => 'AuthenticationFailedException',
      _i61.DataRightsException => 'DataRightsException',
      _i62.EndpointDisabledException => 'EndpointDisabledException',
      _i63.EnrollmentException => 'EnrollmentException',
      _i64.MfaEnrollmentRequiredException => 'MfaEnrollmentRequiredException',
      _i65.MfaRequiredException => 'MfaRequiredException',
      _i66.NoticeDeliveryException => 'NoticeDeliveryException',
      _i67.OtpRequestException => 'OtpRequestException',
      _i68.SessionExpiredException => 'SessionExpiredException',
      _i69.MicroArea => 'MicroArea',
      _i70.OtpChallenge => 'OtpChallenge',
      _i71.Patient => 'Patient',
      _i72.PushToken => 'PushToken',
      _i73.StaffAccount => 'StaffAccount',
      _i74.TriageAnswer => 'TriageAnswer',
      _i75.TriageSession => 'TriageSession',
      _i76.Ubs => 'Ubs',
      _i77.User => 'User',
      _i78.UserCredential => 'UserCredential',
      _i79.Visit => 'Visit',
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
      case _i4.AcsRefreshToken():
        return 'AcsRefreshToken';
      case _i5.AcsUploadToken():
        return 'AcsUploadToken';
      case _i6.Alert():
        return 'Alert';
      case _i7.AlertDeliveryRecord():
        return 'AlertDeliveryRecord';
      case _i8.AlertIdempotencyKey():
        return 'AlertIdempotencyKey';
      case _i9.AlertOutboxEntry():
        return 'AlertOutboxEntry';
      case _i10.AdminAcs():
        return 'AdminAcs';
      case _i11.AdminAcsCreationResult():
        return 'AdminAcsCreationResult';
      case _i12.AdminAlert():
        return 'AdminAlert';
      case _i13.AdminAlertPage():
        return 'AdminAlertPage';
      case _i14.AdminAuditEntry():
        return 'AdminAuditEntry';
      case _i15.AdminAuditPage():
        return 'AdminAuditPage';
      case _i16.AdminDataSubjectRequest():
        return 'AdminDataSubjectRequest';
      case _i17.AdminDataSubjectRequestDetail():
        return 'AdminDataSubjectRequestDetail';
      case _i18.AdminDataSubjectRequestPage():
        return 'AdminDataSubjectRequestPage';
      case _i19.AdminIndicators():
        return 'AdminIndicators';
      case _i20.AdminMicroArea():
        return 'AdminMicroArea';
      case _i21.AdminPasswordResetResult():
        return 'AdminPasswordResetResult';
      case _i22.AdminStaff():
        return 'AdminStaff';
      case _i23.AdminStaffMfaResetResult():
        return 'AdminStaffMfaResetResult';
      case _i24.AlertAckResult():
        return 'AlertAckResult';
      case _i25.AlertStatusResult():
        return 'AlertStatusResult';
      case _i26.DevelopmentLoginResult():
        return 'DevelopmentLoginResult';
      case _i27.EnrollmentResult():
        return 'EnrollmentResult';
      case _i28.EnrollmentTokenResult():
        return 'EnrollmentTokenResult';
      case _i29.MicroAreaPatient():
        return 'MicroAreaPatient';
      case _i30.NoticeSendResult():
        return 'NoticeSendResult';
      case _i31.PatientConsentRecord():
        return 'PatientConsentRecord';
      case _i32.PatientDataOverview():
        return 'PatientDataOverview';
      case _i33.PatientDataSubjectRequestRecord():
        return 'PatientDataSubjectRequestRecord';
      case _i34.PatientRiskEvent():
        return 'PatientRiskEvent';
      case _i35.RedAlertResult():
        return 'RedAlertResult';
      case _i36.ServiceHealth():
        return 'ServiceHealth';
      case _i37.TermsChangeNotice():
        return 'TermsChangeNotice';
      case _i38.TotpEnrollmentStart():
        return 'TotpEnrollmentStart';
      case _i39.TriageResult():
        return 'TriageResult';
      case _i40.UbsContact():
        return 'UbsContact';
      case _i41.VisitSyncEntry():
        return 'VisitSyncEntry';
      case _i42.VisitSyncResult():
        return 'VisitSyncResult';
      case _i43.AuditLog():
        return 'AuditLog';
      case _i44.ConsentLog():
        return 'ConsentLog';
      case _i45.DataSubjectRequest():
        return 'DataSubjectRequest';
      case _i46.EnrollmentToken():
        return 'EnrollmentToken';
      case _i47.AlertStatus():
        return 'AlertStatus';
      case _i48.ArrivalMethod():
        return 'ArrivalMethod';
      case _i49.ConsentPurpose():
        return 'ConsentPurpose';
      case _i50.DataSubjectRequestStatus():
        return 'DataSubjectRequestStatus';
      case _i51.DataSubjectRequestType():
        return 'DataSubjectRequestType';
      case _i52.RiskLevel():
        return 'RiskLevel';
      case _i53.SyncStatus():
        return 'SyncStatus';
      case _i54.UserRole():
        return 'UserRole';
      case _i55.VisitAuthorship():
        return 'VisitAuthorship';
      case _i56.AdminInvalidRequestException():
        return 'AdminInvalidRequestException';
      case _i57.AlertDispatchUnavailableException():
        return 'AlertDispatchUnavailableException';
      case _i58.AlertPermissionException():
        return 'AlertPermissionException';
      case _i59.AlertValidationException():
        return 'AlertValidationException';
      case _i60.AuthenticationFailedException():
        return 'AuthenticationFailedException';
      case _i61.DataRightsException():
        return 'DataRightsException';
      case _i62.EndpointDisabledException():
        return 'EndpointDisabledException';
      case _i63.EnrollmentException():
        return 'EnrollmentException';
      case _i64.MfaEnrollmentRequiredException():
        return 'MfaEnrollmentRequiredException';
      case _i65.MfaRequiredException():
        return 'MfaRequiredException';
      case _i66.NoticeDeliveryException():
        return 'NoticeDeliveryException';
      case _i67.OtpRequestException():
        return 'OtpRequestException';
      case _i68.SessionExpiredException():
        return 'SessionExpiredException';
      case _i69.MicroArea():
        return 'MicroArea';
      case _i70.OtpChallenge():
        return 'OtpChallenge';
      case _i71.Patient():
        return 'Patient';
      case _i72.PushToken():
        return 'PushToken';
      case _i73.StaffAccount():
        return 'StaffAccount';
      case _i74.TriageAnswer():
        return 'TriageAnswer';
      case _i75.TriageSession():
        return 'TriageSession';
      case _i76.Ubs():
        return 'Ubs';
      case _i77.User():
        return 'User';
      case _i78.UserCredential():
        return 'UserCredential';
      case _i79.Visit():
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
    if (dataClassName == 'AcsRefreshToken') {
      return deserialize<_i4.AcsRefreshToken>(data['data']);
    }
    if (dataClassName == 'AcsUploadToken') {
      return deserialize<_i5.AcsUploadToken>(data['data']);
    }
    if (dataClassName == 'Alert') {
      return deserialize<_i6.Alert>(data['data']);
    }
    if (dataClassName == 'AlertDeliveryRecord') {
      return deserialize<_i7.AlertDeliveryRecord>(data['data']);
    }
    if (dataClassName == 'AlertIdempotencyKey') {
      return deserialize<_i8.AlertIdempotencyKey>(data['data']);
    }
    if (dataClassName == 'AlertOutboxEntry') {
      return deserialize<_i9.AlertOutboxEntry>(data['data']);
    }
    if (dataClassName == 'AdminAcs') {
      return deserialize<_i10.AdminAcs>(data['data']);
    }
    if (dataClassName == 'AdminAcsCreationResult') {
      return deserialize<_i11.AdminAcsCreationResult>(data['data']);
    }
    if (dataClassName == 'AdminAlert') {
      return deserialize<_i12.AdminAlert>(data['data']);
    }
    if (dataClassName == 'AdminAlertPage') {
      return deserialize<_i13.AdminAlertPage>(data['data']);
    }
    if (dataClassName == 'AdminAuditEntry') {
      return deserialize<_i14.AdminAuditEntry>(data['data']);
    }
    if (dataClassName == 'AdminAuditPage') {
      return deserialize<_i15.AdminAuditPage>(data['data']);
    }
    if (dataClassName == 'AdminDataSubjectRequest') {
      return deserialize<_i16.AdminDataSubjectRequest>(data['data']);
    }
    if (dataClassName == 'AdminDataSubjectRequestDetail') {
      return deserialize<_i17.AdminDataSubjectRequestDetail>(data['data']);
    }
    if (dataClassName == 'AdminDataSubjectRequestPage') {
      return deserialize<_i18.AdminDataSubjectRequestPage>(data['data']);
    }
    if (dataClassName == 'AdminIndicators') {
      return deserialize<_i19.AdminIndicators>(data['data']);
    }
    if (dataClassName == 'AdminMicroArea') {
      return deserialize<_i20.AdminMicroArea>(data['data']);
    }
    if (dataClassName == 'AdminPasswordResetResult') {
      return deserialize<_i21.AdminPasswordResetResult>(data['data']);
    }
    if (dataClassName == 'AdminStaff') {
      return deserialize<_i22.AdminStaff>(data['data']);
    }
    if (dataClassName == 'AdminStaffMfaResetResult') {
      return deserialize<_i23.AdminStaffMfaResetResult>(data['data']);
    }
    if (dataClassName == 'AlertAckResult') {
      return deserialize<_i24.AlertAckResult>(data['data']);
    }
    if (dataClassName == 'AlertStatusResult') {
      return deserialize<_i25.AlertStatusResult>(data['data']);
    }
    if (dataClassName == 'DevelopmentLoginResult') {
      return deserialize<_i26.DevelopmentLoginResult>(data['data']);
    }
    if (dataClassName == 'EnrollmentResult') {
      return deserialize<_i27.EnrollmentResult>(data['data']);
    }
    if (dataClassName == 'EnrollmentTokenResult') {
      return deserialize<_i28.EnrollmentTokenResult>(data['data']);
    }
    if (dataClassName == 'MicroAreaPatient') {
      return deserialize<_i29.MicroAreaPatient>(data['data']);
    }
    if (dataClassName == 'NoticeSendResult') {
      return deserialize<_i30.NoticeSendResult>(data['data']);
    }
    if (dataClassName == 'PatientConsentRecord') {
      return deserialize<_i31.PatientConsentRecord>(data['data']);
    }
    if (dataClassName == 'PatientDataOverview') {
      return deserialize<_i32.PatientDataOverview>(data['data']);
    }
    if (dataClassName == 'PatientDataSubjectRequestRecord') {
      return deserialize<_i33.PatientDataSubjectRequestRecord>(data['data']);
    }
    if (dataClassName == 'PatientRiskEvent') {
      return deserialize<_i34.PatientRiskEvent>(data['data']);
    }
    if (dataClassName == 'RedAlertResult') {
      return deserialize<_i35.RedAlertResult>(data['data']);
    }
    if (dataClassName == 'ServiceHealth') {
      return deserialize<_i36.ServiceHealth>(data['data']);
    }
    if (dataClassName == 'TermsChangeNotice') {
      return deserialize<_i37.TermsChangeNotice>(data['data']);
    }
    if (dataClassName == 'TotpEnrollmentStart') {
      return deserialize<_i38.TotpEnrollmentStart>(data['data']);
    }
    if (dataClassName == 'TriageResult') {
      return deserialize<_i39.TriageResult>(data['data']);
    }
    if (dataClassName == 'UbsContact') {
      return deserialize<_i40.UbsContact>(data['data']);
    }
    if (dataClassName == 'VisitSyncEntry') {
      return deserialize<_i41.VisitSyncEntry>(data['data']);
    }
    if (dataClassName == 'VisitSyncResult') {
      return deserialize<_i42.VisitSyncResult>(data['data']);
    }
    if (dataClassName == 'AuditLog') {
      return deserialize<_i43.AuditLog>(data['data']);
    }
    if (dataClassName == 'ConsentLog') {
      return deserialize<_i44.ConsentLog>(data['data']);
    }
    if (dataClassName == 'DataSubjectRequest') {
      return deserialize<_i45.DataSubjectRequest>(data['data']);
    }
    if (dataClassName == 'EnrollmentToken') {
      return deserialize<_i46.EnrollmentToken>(data['data']);
    }
    if (dataClassName == 'AlertStatus') {
      return deserialize<_i47.AlertStatus>(data['data']);
    }
    if (dataClassName == 'ArrivalMethod') {
      return deserialize<_i48.ArrivalMethod>(data['data']);
    }
    if (dataClassName == 'ConsentPurpose') {
      return deserialize<_i49.ConsentPurpose>(data['data']);
    }
    if (dataClassName == 'DataSubjectRequestStatus') {
      return deserialize<_i50.DataSubjectRequestStatus>(data['data']);
    }
    if (dataClassName == 'DataSubjectRequestType') {
      return deserialize<_i51.DataSubjectRequestType>(data['data']);
    }
    if (dataClassName == 'RiskLevel') {
      return deserialize<_i52.RiskLevel>(data['data']);
    }
    if (dataClassName == 'SyncStatus') {
      return deserialize<_i53.SyncStatus>(data['data']);
    }
    if (dataClassName == 'UserRole') {
      return deserialize<_i54.UserRole>(data['data']);
    }
    if (dataClassName == 'VisitAuthorship') {
      return deserialize<_i55.VisitAuthorship>(data['data']);
    }
    if (dataClassName == 'AdminInvalidRequestException') {
      return deserialize<_i56.AdminInvalidRequestException>(data['data']);
    }
    if (dataClassName == 'AlertDispatchUnavailableException') {
      return deserialize<_i57.AlertDispatchUnavailableException>(data['data']);
    }
    if (dataClassName == 'AlertPermissionException') {
      return deserialize<_i58.AlertPermissionException>(data['data']);
    }
    if (dataClassName == 'AlertValidationException') {
      return deserialize<_i59.AlertValidationException>(data['data']);
    }
    if (dataClassName == 'AuthenticationFailedException') {
      return deserialize<_i60.AuthenticationFailedException>(data['data']);
    }
    if (dataClassName == 'DataRightsException') {
      return deserialize<_i61.DataRightsException>(data['data']);
    }
    if (dataClassName == 'EndpointDisabledException') {
      return deserialize<_i62.EndpointDisabledException>(data['data']);
    }
    if (dataClassName == 'EnrollmentException') {
      return deserialize<_i63.EnrollmentException>(data['data']);
    }
    if (dataClassName == 'MfaEnrollmentRequiredException') {
      return deserialize<_i64.MfaEnrollmentRequiredException>(data['data']);
    }
    if (dataClassName == 'MfaRequiredException') {
      return deserialize<_i65.MfaRequiredException>(data['data']);
    }
    if (dataClassName == 'NoticeDeliveryException') {
      return deserialize<_i66.NoticeDeliveryException>(data['data']);
    }
    if (dataClassName == 'OtpRequestException') {
      return deserialize<_i67.OtpRequestException>(data['data']);
    }
    if (dataClassName == 'SessionExpiredException') {
      return deserialize<_i68.SessionExpiredException>(data['data']);
    }
    if (dataClassName == 'MicroArea') {
      return deserialize<_i69.MicroArea>(data['data']);
    }
    if (dataClassName == 'OtpChallenge') {
      return deserialize<_i70.OtpChallenge>(data['data']);
    }
    if (dataClassName == 'Patient') {
      return deserialize<_i71.Patient>(data['data']);
    }
    if (dataClassName == 'PushToken') {
      return deserialize<_i72.PushToken>(data['data']);
    }
    if (dataClassName == 'StaffAccount') {
      return deserialize<_i73.StaffAccount>(data['data']);
    }
    if (dataClassName == 'TriageAnswer') {
      return deserialize<_i74.TriageAnswer>(data['data']);
    }
    if (dataClassName == 'TriageSession') {
      return deserialize<_i75.TriageSession>(data['data']);
    }
    if (dataClassName == 'Ubs') {
      return deserialize<_i76.Ubs>(data['data']);
    }
    if (dataClassName == 'User') {
      return deserialize<_i77.User>(data['data']);
    }
    if (dataClassName == 'UserCredential') {
      return deserialize<_i78.UserCredential>(data['data']);
    }
    if (dataClassName == 'Visit') {
      return deserialize<_i79.Visit>(data['data']);
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
      case _i4.AcsRefreshToken:
        return _i4.AcsRefreshToken.t;
      case _i5.AcsUploadToken:
        return _i5.AcsUploadToken.t;
      case _i6.Alert:
        return _i6.Alert.t;
      case _i7.AlertDeliveryRecord:
        return _i7.AlertDeliveryRecord.t;
      case _i8.AlertIdempotencyKey:
        return _i8.AlertIdempotencyKey.t;
      case _i9.AlertOutboxEntry:
        return _i9.AlertOutboxEntry.t;
      case _i43.AuditLog:
        return _i43.AuditLog.t;
      case _i44.ConsentLog:
        return _i44.ConsentLog.t;
      case _i45.DataSubjectRequest:
        return _i45.DataSubjectRequest.t;
      case _i46.EnrollmentToken:
        return _i46.EnrollmentToken.t;
      case _i69.MicroArea:
        return _i69.MicroArea.t;
      case _i70.OtpChallenge:
        return _i70.OtpChallenge.t;
      case _i71.Patient:
        return _i71.Patient.t;
      case _i72.PushToken:
        return _i72.PushToken.t;
      case _i73.StaffAccount:
        return _i73.StaffAccount.t;
      case _i75.TriageSession:
        return _i75.TriageSession.t;
      case _i76.Ubs:
        return _i76.Ubs.t;
      case _i77.User:
        return _i77.User.t;
      case _i78.UserCredential:
        return _i78.UserCredential.t;
      case _i79.Visit:
        return _i79.Visit.t;
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
