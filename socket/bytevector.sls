;; bytevector extensions to r6rs.
;; Written by Jerry 2021
;; SPDX-License-Identifier: Unlicense

(library (ufo-socket socket bytevector)
  (export
    bytevector-slice
    bytevector/null->string)
  (import
    (rnrs))

  ;; Copy the first len bytes from src bytevector into a new bytevector.
  (define bytevector-slice
    (lambda (src len)
      (let ([bv (make-bytevector len)])
        (bytevector-copy! src 0 bv 0 len)
        bv)))

  ;; Like bytevector->string except it ends at the first null source byte.
  ;; O(n) single-pass implementation.
  (define bytevector/null->string
    (lambda (bv)
      (let ([len (bytevector-length bv)])
        (let loop ([i 0])
          (cond
            [(fx=? i len) (utf8->string bv)]
            [(fx=? (bytevector-u8-ref bv i) 0)
             (let ([slice (make-bytevector i)])
               (bytevector-copy! bv 0 slice 0 i)
               (utf8->string slice))]
            [else (loop (fx+ i 1))]))))))

