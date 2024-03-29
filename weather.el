;;; weather.el --- Get weather reports via worldweatheronline.com

;; Copyright: (C) 2012 Jason R. Fruit
;;
;; Author: Jason Fruit
;; URL: http://www.jasonfruit.com/page/weather_el
;; Version: 2012.3.27.2
;;
;;   This program is free software; you can redistribute it and/or
;;   modify it under the terms of the GNU General Public License as
;;   published by the Free Software Foundation; either version 2 of
;;   the License, or (at your option) any later version.
;;   
;;   This program is distributed in the hope that it will be useful,
;;   but WITHOUT ANY WARRANTY; without even the implied warranty of
;;   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
;;   General Public License for more details.
;;   
;;   You should have received a copy of the GNU General Public License
;;   along with GNU Emacs; if not, write to the Free Software
;;   Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
;;   02110-1301 USA

;;; Commentary
;;
;; weather.el uses worldweatheronline.com's JSON API to retrieve
;; weather reports and forecasts.
;;
;; To install, save this file somewhere in your Emacs load
;; path and put the following in your .emacs:
;;
;;   (require 'weather)
;; 
;; To retrieve weather reports, you will have to get an API key from
;; worldweatheronline.com, which requires a free account; the terms
;; and services require that the key not be shared, and I see no other
;; way to comply with that in a free-software use of the API than to
;; require the user to get their own key.  When you've got the key,
;; add to your .emacs:
;;
;;   (setq weather-key "this-is-my-key")
;;
;; replacing this-is-my-key with your API key.  Alternatively, you can
;; use `M-x customize` to set the API key and your preferred unit of
;; distance in the "Weather" group.
;;
;; To get a weather report, do `M-x weather-report` and specify a
;; location using a USA zip code, a UK or Canada postal code, or a
;; city description, e.g. San Bernardino, CA; if you want up to 5 days
;; instead of the default 2 days, do `C-u 5 M-x weather-report`.


(require 'cl)
(require 'json)
(require 'url)

(defgroup weather nil "Options for weather reports")

(defcustom weather-key ""
  "API key from worldweatheronline.com"
  :type '(string)
  :group 'weather)

(defcustom weather-distance-unit "mile"
  "Unit for visibility and wind speed; either mile or km"
  :type '(string)
  :group 'weather)

(defcustom weather-temperature-unit "fahrenheit"
  "Unit for temperature; either fahrenheit or celsius"
  :type '(string)
  :group 'weather)

(defcustom weather-default-city nil
  "Default city for weather information"
  :type '(string)
  :group 'weather)

(defconst weather-distance-alist
  '(("mile" . ((speed . windspeedMiles)
	       (unit . "mph")))
    ("km" . ((speed . windspeedKmph)
	     (unit . "kmph"))))
  "alist to make switch between distance unit easier")

(defconst weather-temperature-alist
  '(("fahrenheit" . ((current . temp_F)
		     (max . tempMaxF)
		     (min . tempMinF)
		     (unit . "F")))
    ("celsius" . ((current . temp_C)
		  (max . tempMaxC)
		  (min . tempMinC)
		  (unit . "C"))))
  "alist to make switch between weather unit easier")

(defconst weather-forecast-template
  (concat "%s: " ; date
	  "%s, " ; weather description
	  "high %s%s, " ; highest temperature with unit
	  "low %s%s, " ; lowest temperature with unit
	  "wind %s " ; wind direction
	  " at "
	  "%s %s, " ; wind speed with unit
	  "precipitation %smm" ; precipitation
	  ".")
  "string template for forecast information")

(defconst weather-current-template
  (concat "Current weather (as of %s ): " ; observation_time
	  "%s, " ; weather description
	  "%s degrees %s, " ; temperature with unit
	  "wind %s at " ; wind direction
	  "%s %s, " ; wind speed with unit
	  "humidity %s%%, " ; humidity
	  "pressure %smb, " ; pressure
	  "precipitation %smm, " ; precipitation
	  "visibility %s%s, " ; visibility and unit
	  "%s%% cloud cover" ; cloud cover
	  ".")
  "string template for current information")

(defun weather-val (key alist)
  "The value part of an alist pairing"
  (cdr (assoc key alist)))

(defun weather-to-nearest-tenth (n)
  "Round n to the nearest tenth, e.g. 5.4432 -> 5.4"
  (/ (fround (* 10 n)) 10))

(defun weather-km-to-miles (distance)
  "convert km to miles"
  (weather-to-nearest-tenth
   (/ distance 1.61)))

(defun weather-format-forecast (record)
  "Format a forecast day record to a sensible string
representation."
  (let* ((d-alist (weather-val weather-distance-unit
			       weather-distance-alist))
	 (d-unit (weather-val 'unit d-alist))
	 (t-alist (weather-val weather-temperature-unit
			       weather-temperature-alist))
	 (t-unit (weather-val 'unit t-alist)))

    (format weather-forecast-template
	    (weather-val 'date record)	; date
	    (weather-val 'value
			 (aref (weather-val 'weatherDesc record)
			       0))	; weather description

	    (weather-val (weather-val 'max
				      t-alist)
			 record)	; max temperature
	    t-unit ; temperature unit

	    (weather-val (weather-val 'min
				      t-alist)
			 record) ; min temperature
	    t-unit
	    
	    (weather-val 'winddir16Point record) ; wind direction
	    (weather-val (weather-val 'speed
				      d-alist)
			 record) ; wind speed
	    d-unit ; disntance unit
	    
	    (weather-val 'precipMM record))))


(defun weather-format-current-weather (record)
  "String representation of current condition record"
  (let* ((d-alist (weather-val weather-distance-unit
			       weather-distance-alist))
	 (d-unit (weather-val 'unit d-alist))
	 (t-alist (weather-val weather-temperature-unit
			       weather-temperature-alist))
	 (t-unit (weather-val 'unit t-alist)))

    (format weather-current-template
	    (weather-val 'observation_time record) ; observation_time
	    (weather-val 'value
			 (aref (weather-val 'weatherDesc
					    record)
			       0)) ; weather description
	    (weather-val (weather-val 'current
				      t-alist)
			 record) ; temperature
	    t-unit ; unit
	    
	    (weather-val 'winddir16Point record) ; windo direction
	    (weather-val (weather-val 'speed
				      d-alist)
			 record) ; wind speed
	    d-unit ; unit
	    (weather-val 'humidity record)
	    (weather-val 'pressure record)
	    (weather-val 'precipMM record)
	    (let* ((visibility (weather-val 'visibility
					    record)) 
		   (visibility-num (string-to-number visibility)))
	      (if (equal weather-distance-unit "mile")
		  (number-to-string (weather-km-to-miles visibility-num))
		visibility)) ; visibility number value
	    d-unit ; visibility unit
	    (weather-val 'cloudcover record))))


(defun weather-report-body (json-obj)
  "Format the body of a weather report from the JSON results"
  (let* ((inner (cdar json-obj))
	 (current (aref (weather-val 'current_condition inner) 0))
	 (forecasts (weather-val 'weather inner)))
    (concat
     ;; the current weather
     (weather-format-current-weather current)
     "\n\n"
     ;; the forecast days
     (apply 'concat
	    (let ((i 0))
	      (loop while (< i (length forecasts))
		    collecting
		    (concat 
		     (weather-format-forecast (aref forecasts i))
		     "\n")
		    doing
		    (setq i (+ i 1))))))))


(defun weather-json-obj (url)
  "Get the JSON results for the specified URL (blocks Emacs)"
  (let ((json-buf (url-retrieve-synchronously url)))
    (save-excursion
      (set-buffer json-buf)
      (json-read-from-string
       (cadr
	(split-string (buffer-string) "\n\n"))))))

(defun weather-url (location days)
  "Build a URL to request the weather JSON for the specified
location and days"
  (concat "http://free.worldweatheronline.com/feed/weather.ashx?q="
	  location
	  "&format=json&num_of_days="
	  (number-to-string days)
	  "&key="
	  weather-key))

(defun weather-report (location &optional days)
  "Get a weather report for the specified location; days defaults
to 2"
  (interactive "sLocation: ")

  ;; escape the location string
  (setq location (url-hexify-string location))

  ;; allow the user to specify days using C-u
  (if (not days)
      (setq days (if current-prefix-arg current-prefix-arg 2)))

  ;; show the weather in the minibuffer (and return it)
  (message "%s"
	   (concat
	    "Weather (via worldweatheronline.com):\n\n"
	    (weather-report-body
	     (weather-json-obj
	      (weather-url location days))))))

(provide 'weather)

;;; weather.el ends here
