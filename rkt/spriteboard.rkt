#lang racket/base
(require racket/flonum
         racket/fixnum
         racket/match
         racket/contract/base
         mode-lambda
         lux)

(define (flsqr x)
  (fl* x x))
(define (fldist x1 x2 y1 y2)
  (flsqrt
   (fl+ (flsqr (fl- x1 x2))
        (flsqr (fl- y1 y2)))))

;; XXX this should not be mutable
(struct clickable (m-spr click! drag-drop! [alive? #:mutable]))
(define (click-click! o)
  ((clickable-click! o)))

(struct draggable ([x #:mutable] [y #:mutable] f-spr
                   drag-start! drag-stop!
                   drag-drop-v drag-drop!
                   alive?))
(define (drag-update-pos! m x y)
  (set-draggable-x! m x)
  (set-draggable-y! m y))
(define (drag-start! m)
  ((draggable-drag-start! m)))
(define (drag-stop! m)
  ((draggable-drag-stop! m)))
(define (drag-value m)
  ((draggable-drag-drop-v m)))

;; This is a type of sprite that is neither draggable nor clickable.
;; However, it is "dropable", in the sense that you can drop another
;; sprite onto it
(struct droppable (m-spr drag-drop! alive?))

;; backgroundable is just a static, "background" sprite with no
;; behavior, except that it can be deleted by setting alive? to #f
(struct backgroundable (m-spr alive?))

(define (object-drop! o v)
  (match o
    [(? clickable?)
     ((clickable-drag-drop! o) v)]
    [(? draggable?)
     ((draggable-drag-drop! o) v)]
    [(? droppable?)
     ((droppable-drag-drop! o) v)]))

(define (force-meta-spr m)
  (if (procedure? m)
    (m)
    m))

(define (object-spr dragged? o)
  (match o
    [(? clickable?)
     (force-meta-spr (clickable-m-spr o))]
    [(? draggable?)
     ((draggable-f-spr o)
      dragged?
      (draggable-x o)
      (draggable-y o))]
    [(? droppable?)
     (force-meta-spr (droppable-m-spr o))]
    [(? backgroundable?)
     (force-meta-spr (backgroundable-m-spr o))]))

(define (object-alive? o)
  (match o
    [(? clickable?)
     ((clickable-alive? o))]
    [(? draggable?)
     ((draggable-alive? o))]
    [(? droppable?) #t]
    [(? backgroundable?)
     ((backgroundable-alive? o))]))

(struct spriteboard (metatree meta->tree) #:mutable)
(define (make-the-spriteboard)
  (spriteboard null (make-hasheq)))
(define (spriteboard-tree dragged-m sb)
  (match-define (spriteboard mt m->t) sb)
  (hash-clear! m->t)
  (for/list ([m (in-list mt)])
    (define t (object-spr (eq? dragged-m m) m))
    (hash-set! m->t m t)
    t))
(define (spriteboard-gc! sb)
  (match-define (spriteboard mt m->t) sb)
  (set-spriteboard-metatree!
   sb
   (for/fold ([mt null])
             ([m (in-list mt)])
     (if (object-alive? m)
         (cons m mt)
         mt))))

(define (spriteboard-clear! sb)
  (match-define (spriteboard mt m->t) sb)
  (hash-clear! m->t)
  (set-spriteboard-metatree! sb '()))

(define (spriteboard-add! sb o)
  (set-spriteboard-metatree!
   sb (cons o (spriteboard-metatree sb)))
  (spriteboard-gc! sb))

(define (spriteboard-clickable!
         sb
         #:sprite m-spr
         #:click! [click! void]
         #:drag-drop! [drag-drop! void]
         #:alive? [alive? (λ () #t)])
  (spriteboard-add!
   sb
   (clickable m-spr click! drag-drop! alive?)))

(define (spriteboard-draggable!
         sb
         #:init-x init-x
         #:init-y init-y
         #:sprite f-spr
         #:drag-start! [drag-start! void]
         #:drag-stop! [drag-stop! void]
         #:drag-drop-v [drag-drop-v void]
         #:drag-drop! [drag-drop! void]
         #:alive? [alive? (λ () #t)])
  (spriteboard-add!
   sb
   (draggable init-x init-y f-spr
              drag-start! drag-stop!
              drag-drop-v drag-drop!
              alive?)))

(define (spriteboard-droppable!
         sb
         #:sprite m-spr
         #:drag-drop! [drag-drop! void]
         #:alive? [alive? (λ () #t)])
  (spriteboard-add!
   sb
   (droppable m-spr drag-drop! alive?)))

(define (spriteboard-backgroundable!
         sb
         #:sprite m-spr
         #:alive? [alive? (λ () #t)])
  (spriteboard-add!
   sb
   (backgroundable m-spr alive?)))

(define (sprite-inside? csd t x y)
  (define t-idx (sprite-data-spr t))

  (define tcx (sprite-data-dx t))
  (define sw (fx->fl (sprite-width csd t-idx)))
  (define tw (fl* (sprite-data-mx t) sw))
  (define thw (fl/ tw 2.0))
  (define x-min (fl- tcx thw))
  (define x-max (fl+ tcx thw))

  (define tcy (sprite-data-dy t))
  (define sh (fx->fl (sprite-height csd t-idx)))
  (define th (fl* (sprite-data-my t) sh))
  (define thh (fl/ th 2.0))
  (define y-min (fl- tcy thh))
  (define y-max (fl+ tcy thh))

  (and (fl<= x-min x)
       (fl<= x x-max)
       (fl<= y-min y)
       (fl<= y y-max)))

(define (make-spriteboard W H csd render initialize!)
  (define std-layer
    (layer (fx->fl (/ W 2)) (fx->fl (/ H 2))))
  (define layer-c
    (make-vector 8 std-layer))
  (define the-sb (make-the-spriteboard))
  (define dragged-m #f)

  (define (find-object not-o x y)
    (define m->t (spriteboard-meta->tree the-sb))
    (for/or ([m (in-list (spriteboard-metatree the-sb))]
             #:unless not-o)
      (define t (hash-ref m->t m #f))
      (and t
           (or (clickable? m) (draggable? m))
           (sprite-inside? csd t x y)
           m)))

  (struct app ()
    #:methods gen:word
    [(define (word-fps w) 30.0)
     (define (word-label w ft)
       (lux-standard-label "Spriteboard" ft))
     (define (word-output w)
       (render layer-c '() (spriteboard-tree dragged-m the-sb)))
     (define (word-event w e)
       (match e
         [(vector 'down x y)
          (define target-m (find-object #f x y))
          (when target-m
            (cond
              [(clickable? target-m)
               (click-click! target-m)]
              [(draggable? target-m)
               (set! dragged-m target-m)
               (drag-update-pos! dragged-m x y)
               (drag-start! dragged-m)]))]
         [(vector 'drag x y)
          (when dragged-m
            (drag-update-pos! dragged-m x y))]
         [(vector 'up x y)
          (when dragged-m
            (drag-update-pos! dragged-m x y)
            (define target-m
              (find-object dragged-m x y))
            (when target-m
              (object-drop! target-m (drag-value dragged-m)))
            (drag-stop! dragged-m)
            (set! dragged-m #f))])
       (spriteboard-gc! the-sb)
       w)
     (define (word-tick w)
       w)])
  (initialize! the-sb)
  (app))

(provide
 ;; XXX these should not be exposed
 set-clickable-alive?!
 spriteboard-metatree
 clickable-m-spr)

(define meta-sprite-data/c
  (or/c sprite-data? (-> sprite-data?)))

(provide
 (contract-out
  [spriteboard-clear!
   (-> spriteboard?
       void?)]
  [spriteboard-clickable!
   (->* (spriteboard?
         #:sprite meta-sprite-data/c)
        (#:click! (-> void?)
         #:drag-drop! (-> any/c void?)
         #:alive? (-> boolean?))
        void?)]
  [spriteboard-draggable!
   (->* (spriteboard?
         #:init-x flonum?
         #:init-y flonum?
         #:sprite (-> boolean? flonum? flonum? sprite-data?))
        (#:drag-start! (-> void?)
         #:drag-stop! (-> void?)
         #:drag-drop-v (-> any/c)
         #:drag-drop! (-> any/c void?)
         #:alive? (-> boolean?))
        void?)]
  [spriteboard-droppable!
   (->* (spriteboard?
         #:sprite meta-sprite-data/c)
        (#:drag-drop! (-> any/c void?)
         #:alive? (-> boolean?))
        void?)]
  [spriteboard-backgroundable!
   (->* (spriteboard?
         #:sprite meta-sprite-data/c)
        (#:alive? (-> boolean?))
        void?)]
  [make-spriteboard
   (-> real? real? compiled-sprite-db? procedure? (-> spriteboard? void?)
       any/c)]))
