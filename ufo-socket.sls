;; -*- mode: scheme; coding: utf-8 -*-
;; Copyright (c) 2024 Guy Q. Schemer
;; SPDX-License-Identifier: MIT
#!r6rs

(library (ufo-socket)
  (export hello)
  (import (rnrs))

(define (hello whom)
  (string-append "Hello " whom "!")))
