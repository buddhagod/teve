;;; Copyright (c) 2012, 2013 Jesper Raftegard <jesper@huggpunkt.org>
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

;;; These procedures actually don't parse HLS playlists. All they
;;; do is pretend.

(module apple-hls-parser (hls-master->streams)
(import scheme chicken srfi-1 srfi-13 data-structures
        miscmacros
        misc-helpers teve-http-client network video)

(define (hls:parse-playlist str)
  (define (read-stream mesh slat)
    (and-let* ((pairs (varlist->alist (string-drop-to mesh ":") ","))
               (res-str (assoc "RESOLUTION" pairs))
               (resolution (or (x-sep-resolution->pair (cdr res-str))
                               (cdr res-str)))
               (bandwidth (assoc "BANDWIDTH" pairs)))
      (make-stream
       (cons 'video-width (car resolution))
       (cons 'video-height (cdr resolution))
       (cons 'bitrate (/ (cdr bandwidth) 1000))
       (cons 'uri (uri-decode-string (car slat))))))
  (let read-entries ((playlist (cdr (string-split str (string #\newline))))
                     (streams '()))
    (cond ((or (null? playlist)
               (null? (cdr playlist)))
           streams)
          (else
           (read-entries (cddr playlist)
                         (if* (read-stream (car playlist) (cdr playlist))
                              (cons it streams)
                              streams))))))

(define (hls-master->streams playlist-uri)
  (let ((playlist (fetch playlist-uri)))
    (if (not (and (string? playlist)
                  (string-contains playlist (string #\newline))))
        #f
        (filter-map
         (lambda (stream)
           (if (not (stream? stream))
               #f
               (update-stream stream
                              (make-stream-value 'stream-type 'hls)
                              (make-stream-value 'master-playlist
                                                 playlist-uri))))
         (hls:parse-playlist playlist)))))

)
