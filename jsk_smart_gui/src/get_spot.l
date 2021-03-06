#!/usr/bin/env roseus
(ros::load-ros-manifest "jsk_smart_gui")
;; Load this when creating jsk_maps' spots
(ros::roseus "spot-creator")
;;(require "package://euslib/irteus_proposals/string.l")

(defun split-string (str &optional (separator #\ ))
  (let ((chars (coerce str cons)))
    (labels ((rec (rest-chars processing result)
               (cond ((null rest-chars)
                      (append result (list processing)))
                     ((= (car rest-chars) separator)
                      (rec (cdr rest-chars)
                           nil
                           (append result (list processing))))
                     (t
                      (rec (cdr rest-chars)
                           (append processing (list (car rest-chars)))
                           result)))))
      (mapcar #'(lambda (x)
                  (coerce x string))
              (rec chars nil nil)))))
(defun string-left= (match str)
  (let ((match-length (length match)))
    (string= match (subseq str 0 match-length))))

(defun string-right= (match str)
  (let ((match-length (length match)))
    (string= match (subseq str (- (length str) match-length)))))


#|
rostopic pub "/Tablet/GetSpot" std_msgs/Empty  -1
|#

(defun spot-init-setting ()
  (ros::subscribe "/Tablet/GetSpot"
		  std_msgs::Empty #'get-spot-cb)
  (defvar *tfl* (instance ros::transform-listener :init))
  (setq *time-count* (ros::time-now))
  ;;(make-spots-js (get-current-spot))
  (make-spots-yaml (get-current-spot)))

(defun spot-execute-main ()
  (ros::rate 10)
  (ros::ros-info "get_spot::start running")
  (while (ros::ok)
    (ros::spin-once)
    (ros::sleep)
    ))

(defun get-spot-cb (msg)
  (ros::ros-info "make-temp-spots-cb called")
  (make-temp-spots-cb))

;; load eng*-scene.l , make *scene* and return spots
(defun get-current-spot ()
  ;;(place (ros::get-param "map_server/frame_id")
  (let ((place "/eng2") spots)
    (cond ((null place)
	   (ros::ros-warn "get_spot:: Could not get current place")
	   (setq spots (list "/unknown/unknown/unknown")))
	  (t
	   (ros::ros-info "get_spot:: the robot is in ~A now" place)
	   (load (ros::resolve-ros-path (format nil "package://jsk_maps/src/~A-scene.l" place)))
	   (setq *scene* (eval (read-from-string (format nil "(make-~A-scene)" (string-left-trim "/" place)))))
	   (setq spots (mapcar #'(lambda(x) (send x :name)) (flatten (mapcar #'(lambda(x) (if (find-method x :spot) (send x :spots))) (send *scene* :objects)))))
	   ))
    spots))

;; create spots.js in jsk_ipad_gui/jslib
(defun make-spots-js (spots)
  (let* ((js_dir (ros::resolve-ros-path (format nil "package://jsk_ipad_gui/src/jsk_ipad_gui/jslib")))
	 (js_file (format nil "~A/spots.js" js_dir)))
    (ros::ros-info "tablet_receiver:: creating spots.js for tablet")
    (with-open-file
     (f js_file :direction :output)
     (format f "current_spots = new Array(~%")
     (format f "\"~A\"~%" (car spots))
     (dolist (spot (cdr spots))
       (format f ",\"~A\"~%" spot))
     (format f ")~%"))
    ))

;; create jsk_spots.yaml in jsk_android_gui
(defun make-spots-yaml (spots &key (remove-panel t))
  (let* ((yaml_dir (ros::resolve-ros-path (format nil "package://jsk_android_gui")))
	 (yaml_file (format nil "~A/jsk_spots.yaml" yaml_dir))
	 buildings floors)
    (ros::ros-info "tablet_receiver:: creating jsk_spots.yaml for tablet")
    (dolist (spot spots)
      (let ((ss (split-string spot #\/))
	    (building-exist-flag nil) (floor-exist-flag nil))
	(when (eq (length ss) 4)
	  (mapcar #'(lambda(x) (if (equal (elt ss 1) x) (setq building-exist-flag t))) buildings)
	  (mapcar #'(lambda(x) (if (equal (elt ss 2) x) (setq floor-exist-flag t))) floors)
	  (unless building-exist-flag (push (elt ss 1) buildings))
	  (unless floor-exist-flag (push (elt ss 2) floors))
	  )))
    (print (list buildings floors))
    (with-open-file
     (f yaml_file :direction :output)
     (dolist (building (reverse buildings))
       (format f "~A:~%" building)
       (dolist (floor (reverse floors))
	 (let (existed-spot)
	   (dolist (spot spots)
	     (if (string-left= (format nil "/~A/~A/" building floor) spot)
		 (if (and remove-panel
			    (or (string-right= "call_panel" spot)
				(string-right= "inside_panel" spot)
				(string-right= "panel-front" spot)))
		       (format nil "removing panel spots when makeing yaml")
		     (push spot existed-spot))))
	   (when existed-spot
	     (format f "    ~A:~%" floor)
	     (format f "      spots: [")
	     (format f "~A" (car existed-spot))
	     (dolist (spot (cdr existed-spot))
	       (format f ", ~A" spot))
	     (format f "]~%"))
	   ))))
    ))

(defun make-temp-spots-cb ()
  (let* ((mappose (send *tfl* :lookup-transform "/map" "/base_link"  (ros::time 0)))
	 (js_dir (ros::resolve-ros-path (format nil "package://jsk_maps/src")))
	 (js_file (format nil "~A/temp-scene.l" js_dir)))
    (if (null mappose)
	(progn (ros::ros-warn "robot not localized")
	       (return-from make-temp-spots-cb nil)))

    (unless (boundp '*temp-spots*)
      (setq *temp-spots* nil))
    (ros::ros-info "*temp-spots* : ~A" *temp-spots*)
    (push (list (send mappose :rot) (send mappose :pos)) *temp-spots*)
    ;; *temp-spots* : '('(rot pos) '(rot pos))
    (ros::ros-info "get_spot:: creating temp spots for Tablet")
    (with-open-file
     (f js_file :direction :output)

     (format f "(defun make-temp-f-scene ()~%")
     (format f " (let (scene map)~%")
     (format f "  (setq map (make-floor-plane (ros::resolve-ros-path \"package://jsk_maps/raw_maps/eng2-2f-0.05.pgm\") 50 -13000 -48500 :name \"/temp/f/floor-plane\")) ;;need this? ~%")
     (format f "  (make-cascoords-tree map ~%")
     (dotimes (i (length *temp-spots*))
       (let* ((spot (elt *temp-spots* i)) (spot-pos (cadr spot)))
	 (format f "`(:rot ~A :pos ,(float-vector ~A ~A ~A) :name \"/temp/f/place~A\")~%" (car spot) (aref spot-pos 0) (aref spot-pos 1) (aref spot-pos 2) i)))
     (format f "  ) ~%")
     (format f "  (setq scene (instance nav-scene-model :init :name \"/temp/f\" :objects (append (list map) (send map :descendants)))) ~%")
     (format f "  (send scene :map map) ;;need this? ~%")
     (format f "scene)) ~%")
     (format f "(defun make-temp-scene () ~%")
     (format f " (let (scene maps)  ~%")
     (format f "  (setq maps (list (make-temp-f-scene))) ~%")
     (format f "  (setq scene (instance building-model :init :name \"/temp\" :objects maps)) ~%")
     (format f ")) ~%")
     )
    (unix:sleep 1)
    (load js_file)
    (let* ((spots (mapcar #'(lambda(x) (send x :name)) (flatten (mapcar #'(lambda(x) (if (find-method x :spot) (send x :spots))) (send *scene* :objects)))))
	   (temp-scene (make-temp-scene))
	   (temp-spots (mapcar #'(lambda(x) (send x :name)) (flatten (mapcar #'(lambda(x) (if (find-method x :spot) (send x :spots))) (send temp-scene :objects))))))
      (make-spots-js temp-spots)
      (make-spots-yaml (append spots temp-spots))
      (speak-jp "とうろくしました")
      )))
