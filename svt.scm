;;; Copyright (c) 2012 Jesper Raftegard <jesper@huggpunkt.org>
;;;
;;; Permission to use, copy, modify, and distribute this software for any
;;; purpose with or without fee is hereby granted, provided that the above
;;; copyright notice and this permission notice appear in all copies.
;;;
;;; THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
;;; WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
;;; MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
;;; ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
;;; WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
;;; ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
;;; OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

(require-extension srfi-12 srfi-13)
(require-extension http-client uri-common)

(include "misc-helpers.scm")
(include "apple-hls.scm")

;;; Get JSON-data from SVT Play
;;; Return values:
;;;   A list/alist tree         (if valid JSON data is available for url)
;;;   #f                        (otherwise)
(define (svt:download-json-data url)
  (download-json (add-http-get-query-var url "output" "json")))

(define (find-first-quoted-swf)
  (let ((ending (string-reverse ".swf")))
    (let find-first-swf ((stack "")
                         (is-discarding #t)
                         (ch (read-char)))
      (cond
       ((eof-object? ch) #f)
       ((and (char=? #\" ch) (string-prefix? ending stack))
        (let discard-until-eof ((ch (read-char)))
          (if (eof-object? ch)
              (string-reverse stack)
              (discard-until-eof (read-char)))))
       (else
        (find-first-swf (if is-discarding "" (conc ch stack))
                        (not-if (char=? #\" ch) is-discarding)
                        (read-char)))))))

(define (svt:swf-player-for url)
  (and-let* ((swf (with-input-from-request url #f find-first-quoted-swf)))
    (conc "http://www.svtplay.se" swf)))

(define (svt:stream-type-of url bitrate player-type)
  (let ((protocol (url->protocol url)))
    (cond
     ((string=? player-type "ios")
      'hls)
     ((and (string=? player-type "wmv")
           (string-prefix? "http" protocol))
      'http)
     ((and (string=? player-type "mpeg4")
           (string=? protocol "rtsp"))
      'rtsp)
     ((and (string=? player-type "flash")
           (string-prefix? "rtmp" protocol))
      'rtmp)
     ((and (string=? player-type "flash")
           (string-prefix? "http" protocol))
      (if (string-suffix? ".f4m" url)
          'hds
          'http))
     ((and (string=? player-type "wmv")
           (string=? protocol "mms"))
      'mms)
     (else
      #f))))

(define (svt:json-data->video json-data)
  (let* ((subtitles (json-ref json-data "video" "subtitleReferences" 0 "url"))
         (popout-url (json-ref json-data "context" "popoutUrl"))
         (play-url (if popout-url
                       (conc "http://www.svtplay.se" popout-url)
                       #f)))
    (remove not
            (fold (lambda (raw videos)
                    (let* ((url (assoc "url" raw))
                           (bitrate (assoc "bitrate" raw))
                           (player-type (assoc "playerType" raw))
                           ;; This might fail, obviously.
                           (stream-type (svt:stream-type-of (cdr url)
                                                            (cdr bitrate)
                                                            (cdr player-type))))
                      (if (and url (eq? stream-type 'hls))
                          (append
                           (remove not
                                   (map (lambda (x)
                                          (cons (cons 'stream-type 'hls)
                                                (cons (if subtitles
                                                          (cons 'subtitles
                                                                subtitles)
                                                          #f)
                                                      x)))
                                        (hls-master->video (cdr url))))
                           videos)
                          (cons
                           (remove not
                                   (list
                                    (if url
                                        (cons 'url
                                              (conc (uri-decode-string (cdr url))
                                                    (if (eqv? stream-type 'hds)
                                                        "?hdcore"
                                                        "")))
                                        #f)
                                    (if (and bitrate
                                             (< 0 (cdr bitrate)))
                                        (cons 'bitrate (cdr bitrate)) #f)
                                    (if subtitles
                                        (cons 'subtitles subtitles) #f)
                                    (if stream-type
                                        (cons 'stream-type stream-type) #f)
                                    (cons 'view-at play-url)
                                    (if (eq? stream-type 'rtmp)
                                        (cons 'swf-player
                                              (svt:swf-player-for play-url))
                                        #f)))
                           videos))))
                  '()
                  (json-ref json-data "video" "videoReferences")))))
