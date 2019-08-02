// Copyright 2019 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:cocoon_service/src/request_handling/body.dart';
import 'package:cocoon_service/src/request_handling/request_handler.dart';
import 'package:meta/meta.dart';

import 'fake_http.dart';
import 'fake_logging.dart';

class RequestHandlerTester {
  RequestHandlerTester({
    this.request,
    FakeHttpResponse response,
    FakeLogging log,
  })  : log = log ?? FakeLogging(),
        response = response ?? FakeHttpResponse();

  HttpRequest request;
  FakeHttpResponse response;
  FakeLogging log;

  Future<T> get<T extends Body>(RequestHandler<T> handler) {
    return run<T>(() {
      return handler.get(); // ignore: invalid_use_of_protected_member
    });
  }

  Future<T> post<T extends Body>(RequestHandler<T> handler) {
    return run<T>(() {
      return handler.post(); // ignore: invalid_use_of_protected_member
    });
  }

  @protected
  Future<T> run<T extends Body>(Future<T> callback()) {
    return runZoned<Future<T>>(() {
      return callback();
    }, zoneValues: <RequestKey<dynamic>, Object>{
      RequestKey.request: request,
      RequestKey.response: response,
      RequestKey.log: log,
    });
  }
}