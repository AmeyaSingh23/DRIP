import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:workmanager/workmanager.dart';

import '../../../core/network/api_client.dart';
import '../../../core/storage/secure_token_storage.dart';
import '../domain/clothing_item_draft.dart';
import 'wardrobe_repository.dart';

const wardrobeUploadTaskName = 'drip.wardrobe-upload';

enum BackgroundUploadStatus {
  queued,
  completed,
  manualRequired,
  rejected,
  failed,
}

class BackgroundUploadJob {
  const BackgroundUploadJob({
    required this.id,
    required this.idempotencyKey,
    required this.ownerEmail,
    required this.cutoutPath,
    required this.mode,
    required this.status,
    this.taggingImagePath,
    this.itemName,
    this.category,
    this.customCategory,
    this.color,
    this.error,
    this.response,
    this.attempts = 0,
  });

  final String id;
  final String idempotencyKey;
  final String ownerEmail;
  final String cutoutPath;
  final String? taggingImagePath;
  final String mode;
  final BackgroundUploadStatus status;
  final String? itemName;
  final String? category;
  final String? customCategory;
  final String? color;
  final String? error;
  final Map<String, dynamic>? response;
  final int attempts;

  ClothingItemDraft? get completedDraft =>
      response == null ? null : ClothingItemDraft.fromJson(response!);

  BackgroundUploadJob copyWith({
    BackgroundUploadStatus? status,
    String? error,
    Map<String, dynamic>? response,
    int? attempts,
  }) => BackgroundUploadJob(
    id: id,
    idempotencyKey: idempotencyKey,
    ownerEmail: ownerEmail,
    cutoutPath: cutoutPath,
    taggingImagePath: taggingImagePath,
    mode: mode,
    status: status ?? this.status,
    itemName: itemName,
    category: category,
    customCategory: customCategory,
    color: color,
    error: error,
    response: response ?? this.response,
    attempts: attempts ?? this.attempts,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'idempotency_key': idempotencyKey,
    'owner_email': ownerEmail,
    'cutout_path': cutoutPath,
    'tagging_image_path': taggingImagePath,
    'mode': mode,
    'status': status.name,
    'item_name': itemName,
    'category': category,
    'custom_category': customCategory,
    'color': color,
    'error': error,
    'response': response,
    'attempts': attempts,
  };

  factory BackgroundUploadJob.fromJson(Map<String, dynamic> json) =>
      BackgroundUploadJob(
        id: json['id'] as String,
        idempotencyKey: json['idempotency_key'] as String,
        // Jobs written by an earlier app build do not contain an owner. They
        // are treated as unsafe and fail closed in the worker instead of
        // risking an upload to the currently signed-in account.
        ownerEmail: json['owner_email'] as String? ?? '',
        cutoutPath: json['cutout_path'] as String,
        taggingImagePath: json['tagging_image_path'] as String?,
        mode: json['mode'] as String,
        status: BackgroundUploadStatus.values.byName(json['status'] as String),
        itemName: json['item_name'] as String?,
        category: json['category'] as String?,
        customCategory: json['custom_category'] as String?,
        color: json['color'] as String?,
        error: json['error'] as String?,
        response: (json['response'] as Map?)?.cast<String, dynamic>(),
        attempts: (json['attempts'] as num?)?.toInt() ?? 0,
      );
}

class BackgroundUploadQueue {
  static const _folderName = 'wardrobe_upload_jobs';

  Future<BackgroundUploadJob> enqueueAuto({
    required String id,
    required String idempotencyKey,
    required String ownerEmail,
    required File cutout,
    required File taggingImage,
  }) => _enqueue(
    BackgroundUploadJob(
      id: id,
      idempotencyKey: idempotencyKey,
      ownerEmail: ownerEmail,
      cutoutPath: '',
      taggingImagePath: '',
      mode: 'auto',
      status: BackgroundUploadStatus.queued,
    ),
    cutout: cutout,
    taggingImage: taggingImage,
  );

  Future<BackgroundUploadJob> enqueueManual({
    required String id,
    required String idempotencyKey,
    required String ownerEmail,
    required File cutout,
    required String itemName,
    required String category,
    required String color,
    String? customCategory,
  }) => _enqueue(
    BackgroundUploadJob(
      id: id,
      idempotencyKey: idempotencyKey,
      ownerEmail: ownerEmail,
      cutoutPath: '',
      mode: 'manual',
      status: BackgroundUploadStatus.queued,
      itemName: itemName,
      category: category,
      color: color,
      customCategory: customCategory,
    ),
    cutout: cutout,
  );

  Future<BackgroundUploadJob> _enqueue(
    BackgroundUploadJob draft, {
    required File cutout,
    File? taggingImage,
  }) async {
    final directory = await _jobsDirectory();
    final cutoutPath =
        '${directory.path}${Platform.pathSeparator}${draft.id}.png';
    await cutout.copy(cutoutPath);
    String? taggingPath;
    if (taggingImage != null) {
      taggingPath = '${directory.path}${Platform.pathSeparator}${draft.id}.jpg';
      await taggingImage.copy(taggingPath);
    }
    final job = BackgroundUploadJob(
      id: draft.id,
      idempotencyKey: draft.idempotencyKey,
      ownerEmail: draft.ownerEmail,
      cutoutPath: cutoutPath,
      taggingImagePath: taggingPath,
      mode: draft.mode,
      status: draft.status,
      itemName: draft.itemName,
      category: draft.category,
      customCategory: draft.customCategory,
      color: draft.color,
    );
    await save(job);
    await Workmanager().registerOneOffTask(
      'wardrobe-upload-${job.id}',
      wardrobeUploadTaskName,
      inputData: {'job_id': job.id},
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.keep,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(seconds: 15),
      tag: wardrobeUploadTaskName,
    );
    return job;
  }

  Future<BackgroundUploadJob?> read(String id) async {
    final file = await _manifestFile(id);
    if (!await file.exists()) return null;
    final data = jsonDecode(await file.readAsString());
    return data is Map<String, dynamic>
        ? BackgroundUploadJob.fromJson(data)
        : null;
  }

  Future<void> save(BackgroundUploadJob job) async {
    final file = await _manifestFile(job.id);
    await file.writeAsString(jsonEncode(job.toJson()), flush: true);
  }

  Future<void> removeSourceFiles(BackgroundUploadJob job) async {
    for (final path in [job.cutoutPath, job.taggingImagePath]) {
      if (path == null) continue;
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
  }

  Future<File> _manifestFile(String id) async {
    final directory = await _jobsDirectory();
    return File('${directory.path}${Platform.pathSeparator}$id.json');
  }

  Future<Directory> _jobsDirectory() async {
    final root = await getApplicationDocumentsDirectory();
    return Directory('${root.path}${Platform.pathSeparator}$_folderName')
      ..createSync(recursive: true);
  }
}

@pragma('vm:entry-point')
void backgroundUploadDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    if (taskName != wardrobeUploadTaskName) return true;
    final jobId = inputData?['job_id'];
    if (jobId is! String) return true;
    return BackgroundUploadWorker().run(jobId);
  });
}

class BackgroundUploadWorker {
  final _queue = BackgroundUploadQueue();
  final _storage = SecureTokenStorage();
  final _repository = WardrobeRepository(ApiClient());

  Future<bool> run(String jobId) async {
    final job = await _queue.read(jobId);
    if (job == null || job.status == BackgroundUploadStatus.completed) {
      return true;
    }
    final token = await _storage.readAccessToken();
    if (token == null) {
      await _queue.save(
        job.copyWith(
          status: BackgroundUploadStatus.failed,
          error: 'Sign in again before this upload can continue.',
        ),
      );
      return true;
    }

    // WorkManager can resume after the user has signed out and somebody else
    // has signed in on the same phone. Verify job ownership before reading or
    // uploading its image files so photos never cross account boundaries.
    try {
      final response = await ApiClient().dio.get<Map<String, dynamic>>(
        '/api/v1/auth/me',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final activeEmail = response.data?['email'];
      if (activeEmail is! String ||
          activeEmail.toLowerCase() != job.ownerEmail.toLowerCase()) {
        await _queue.save(
          job.copyWith(
            status: BackgroundUploadStatus.failed,
            error:
                'This queued photo belongs to a different signed-in account.',
          ),
        );
        return true;
      }
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) {
        await _queue.save(
          job.copyWith(
            status: BackgroundUploadStatus.failed,
            error: 'Your session ended. Sign in again to upload this item.',
          ),
        );
        return true;
      }
      // Let WorkManager use its constrained exponential retry for a temporary
      // connection failure while checking the active account.
      return false;
    }

    // Auto jobs from an older app version must never bypass the new review
    // screen and upload directly to Cloudinary.
    if (job.mode != 'manual') {
      await _queue.save(
        job.copyWith(
          status: BackgroundUploadStatus.failed,
          error: 'This photo needs review before it can be uploaded.',
        ),
      );
      return true;
    }

    final attempt = job.attempts + 1;
    await _queue.save(job.copyWith(attempts: attempt, error: null));
    try {
      final cutout = File(job.cutoutPath);
      final draft = await _repository.manualUpload(
        cutout: cutout,
        token: token,
        itemName: job.itemName ?? '',
        category: job.category ?? 'Custom',
        color: job.color ?? '',
        customCategory: job.customCategory,
        idempotencyKey: job.idempotencyKey,
      );
      final completed = job.copyWith(
        status: BackgroundUploadStatus.completed,
        response: draft.toJson(),
      );
      await _queue.save(completed);
      await _queue.removeSourceFiles(completed);
      return true;
    } on DioException catch (error) {
      final statusCode = error.response?.statusCode;
      final detail = _detail(error);
      if (statusCode == 422 &&
          detail.startsWith('No clothing item was detected')) {
        final rejected = job.copyWith(
          status: BackgroundUploadStatus.rejected,
          error: detail,
        );
        await _queue.save(rejected);
        await _queue.removeSourceFiles(rejected);
        return true;
      }
      if (statusCode == 401) {
        await _queue.save(
          job.copyWith(
            status: BackgroundUploadStatus.failed,
            error: 'Your session ended. Sign in again to upload this item.',
          ),
        );
        return true;
      }
      if (statusCode == 409) {
        await _queue.save(job.copyWith(error: detail, attempts: attempt));
        return false;
      }
      if (attempt >= 3) {
        await _queue.save(
          job.copyWith(
            status:
                job.mode == 'auto'
                    ? BackgroundUploadStatus.manualRequired
                    : BackgroundUploadStatus.failed,
            error: detail,
            attempts: attempt,
          ),
        );
        return true;
      }
      await _queue.save(job.copyWith(error: detail, attempts: attempt));
      return false;
    } catch (_) {
      await _queue.save(
        job.copyWith(
          status: BackgroundUploadStatus.failed,
          error: 'This upload could not continue. Please try again.',
          attempts: attempt,
        ),
      );
      return true;
    }
  }

  String _detail(DioException error) {
    final data = error.response?.data;
    if (data is Map && data['detail'] is String) {
      return data['detail'] as String;
    }
    return 'The upload is waiting for a reliable connection.';
  }
}
