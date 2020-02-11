// Copyright 2020 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:appengine/appengine.dart';
import 'package:gcloud/db.dart';
import 'package:github/server.dart';
import 'package:googleapis/bigquery/v2.dart';
import 'package:meta/meta.dart';

import '../datastore/cocoon_config.dart';
import '../foundation/providers.dart';
import '../foundation/typedefs.dart';
import '../model/appengine/gold_status_update.dart';
import '../request_handling/api_request_handler.dart';
import '../request_handling/authentication.dart';
import '../request_handling/body.dart';
import '../service/datastore.dart';
import '../service/gold_status_provider.dart';

@immutable
class PushGoldStatusToGithub extends ApiRequestHandler<Body> {
  const PushGoldStatusToGithub(
    Config config,
    AuthenticationProvider authenticationProvider, {
    @visibleForTesting DatastoreServiceProvider datastoreProvider,
    @visibleForTesting LoggingProvider loggingProvider,
      // BuildStatusProvider
    @visibleForTesting GoldStatusProvider goldStatusProvider,
  }) : datastoreProvider = datastoreProvider ?? DatastoreService.defaultProvider,
       loggingProvider = loggingProvider ?? Providers.serviceScopeLogger,
       goldStatusProvider = goldStatusProvider ?? const GoldStatusProvider(),
       super(config: config, authenticationProvider: authenticationProvider);

  final DatastoreServiceProvider datastoreProvider;
  final LoggingProvider loggingProvider;
  final GoldStatusProvider goldStatusProvider;

  @override
  Future<Body> get() async {
    final Logging log = loggingProvider();
    final DatastoreService datastore = datastoreProvider();

    if (authContext.clientContext.isDevelopmentEnvironment) {
      // Don't push GitHub status from the local dev server.
      return Body.empty;
    }

    const RepositorySlug slug = RepositorySlug('flutter', 'flutter');

    final GitHub github = await config.createGitHubClient();
    // BuilStatusUpdate
    final List<GithubBuildStatusUpdate> updates = <GithubBuildStatusUpdate>[];

    await for (PullRequest pr in github.pullRequests.list(slug)) {
      final GoldStatus goldStatus = await goldStatusProvider.getGoldStatus(pr);
      final GoldStatusUpdate update = await datastore.queryLastGoldStatus(slug, pr);

      if (update.status != buildStatus.githubStatus) {
        log.debug(
          'Updating status of ${slug.fullName}#${pr.number} from ${update.status}');
        final CreateStatus request = CreateStatus(buildStatus.githubStatus);
        request.targetUrl = 'https://flutter-dashboard.appspot.com/build.html';
        request.context = 'flutter-build';
        if (buildStatus != BuildStatus.succeeded) {
          request.description =
          'Flutter build is currently broken. Please do not merge this '
            'PR unless it contains a fix to the broken build.';
        }

        try {
          await github.repositories.createStatus(slug, pr.head.sha, request);
          update.status = buildStatus.githubStatus;
          update.updates += 1;
          updates.add(update);
        } catch (error) {
          log.error(
            'Failed to post status update to ${slug.fullName}#${pr.number}: $error');
        }
      }
    }

    final int maxEntityGroups = config.maxEntityGroups;
    for (int i = 0; i < updates.length; i += maxEntityGroups) {
      await datastore.db.withTransaction<void>((Transaction transaction) async {
        transaction.queueMutations(
          inserts: updates.skip(i).take(maxEntityGroups).toList());
        await transaction.commit();
      });
    }
    log.debug('Committed all updates');

    return Body.empty;
  }
}
