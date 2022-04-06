
    var WEIGHT_KILOGRAM = 0;
    var WEIGHT_STONE = 2;
    var WEIGHT_ABBREVIATIONS = [ "kg", "lb", "st" ];
    var CALORIES_PER_WEIGHT_UNIT = [ 7716, 3500, 3500 ];
    var WEIGHT_CONVERSION = [
    /*  Entries for pounds and stones are identical because
        even if stones are selected, entries in log items are
        always kept in pounds.

       To:         kg               lb             st
                                                                  From   */
              [ 1.0,            2.2046226,     2.2046226    ],  //  kg
              [ 0.45359237,     1.0,           1.0          ],  //  lb
              [ 0.45359237,     1.0,           1.0          ]   //  st
    ];
    var CALORIES_PER_ENERGY_UNIT = [ 1, 0.239045 ];
    var ENERGY_CONVERSION = [
    //
    //  To:         cal         kJ                 From
                [   1.0,        4.18331  ],     //  cal
                [   0.239045,   1.0      ]      //  kJ
    ];

    var U_MINUS_SIGN = "\u2212";

    function initialiseDocument() {
        externalLinks();
        determineTimeZoneOffset();
        if ((typeof setCookie) === (typeof Function)) {
            setCookie();
        }
    }

    function checkSecure() {
        if ((!location.protocol.match(/^https:/i)) &&
            (location.hostname != "server1.fourmilab.ch")) {
            alert("Warning!  This document appears to have been " +
                  "received over an insecure Internet link (http: " +
                  "as opposed to https:).  It is possible the data " +
                  "you submit may be intercepted by an " +
                  "eavesdropper between your computer and The " +
                  "Hacker's Diet Online server.\n\n" +
                  "To be safe, please re-submit your query to the secure server:\n " +
                  "    https://www.fourmilab.ch/cgi-bin/HackDiet");
        }
    }

    var unsavedChanges = 0;

    function countChange() {
        unsavedChanges++;
    }

    function leaveDocument() {
        if (unsavedChanges > 0) {
            return window.confirm("You have " + unsavedChanges +
                " unsaved change" + (unsavedChanges > 1 ? "s" : "") +
                " to this form.  To discard " +
                "these changes and navigate away from this page " +
                "press OK.  Otherwise, press Cancel and save your " +
                "changes before leaving this page.");
        }
    }

    var decimalCharacter = ".";             // User decimal separator character

    function editWeight(weight, unit) {
         if (unit == WEIGHT_STONE) {
            var sgn = (weight < 0) ? "-" : "";
            weight = Math.abs(weight);
            var stones = Math.floor(weight / 14);
            var lbs = weight - (stones * 14);
//alert("Stoner " + weight + "  " + stones + "  " + lbs);
            return (sgn + stones.toFixed(0)) + " " +
                ((lbs < 10) ? " " : "") + lbs.toFixed(1).replace(/\./, decimalCharacter);
         } else {
            return weight.toFixed(1).replace(/\./, decimalCharacter);
        }
    }

    function parseWeight(weight, unit) {
        weight = weight.replace(/,/g, ".");
        if (unit == WEIGHT_STONE) {
            var comp = weight.match(/^\s*(\d+)\s+(\d+\.?\d*)\s*$/);
            if (comp != null) {
                return (Number(comp[1]) * 14) + Number(comp[2]);
            }
//            alert("Sproink (" + weight + ")");
            if (!weight.match(/^\s*(\d+\.?\d*)\s*$/)) {
                return -1;
            }
            return Number(weight) * 14;
         } else {
            if (!weight.match(/^\s*(\d+\.?\d*)\s*$/)) {
                return -1;
            }
            return Number(weight);
        }
    }

    function parseSignedWeight(weight, unit) {
        var sgn = 1;
        var ms = weight.match(/\s*([\+\-])/);
        if (ms != null) {
            if (ms[1] == '-') {
                sgn = -1;
            }
            weight = weight.replace(/\s*[\+\-]/, "");
        }
        return parseWeight(weight, unit) * sgn;
    }

    var fit_n, fit_s1, fit_s2, fit_s3, fit_s4;

    function fitStart() {
        fit_n = fit_s1 = fit_s2 = fit_s3 = fit_s4 = 0;
    }

    function fitAddPoint(value) {
        fit_s1 += (fit_n + 1) * value;
        fit_s2 += (fit_n + 1);
        fit_s3 += value;
        fit_s4 += (fit_n + 1) * (fit_n + 1);
        fit_n++;
    }

    function fitSlope() {
//alert(fit_n + " " + fit_s1 + " " + fit_s2 + " " + fit_s3 + " " + fit_s4);
        return ((fit_s1 * fit_n) - (fit_s2 * fit_s3)) /
                ((fit_s4 * fit_n) - (fit_s2 * fit_s2));
    }

    function expandAbbreviatedWeight(day, unit) {
        var w = document.getElementById("w" + day).value;
        w = w.replace(/^\s+/, "");
        w = w.replace(/\s+$/, "");
        w = w.replace(/,/g, ".");

        //   In stones, all abbreviations have a decimal
        if ((unit == WEIGHT_STONE) && (!w.match(/\d*[\.,]\d*/))) {
            //  Canonicalise weight
            if (w != '') {
                document.getElementById("w" + day).value =
                                editWeight(parseWeight(w, unit), unit);
            }
            return true;
        }

        if ((w == '.') || (w == ',') || (w.match(/^[\.,]\d+$/)) ||
            (w.match(/^\d([\.,]\d*)?$/)) ||
            ((unit == WEIGHT_STONE) && w.match(/^\d\d[\.,]\d*$/))) {
            var p = 0, pd =  0;
            for (var i = day - 1; i >= 1; i--) {
                p = document.getElementById("w" + i).value;
                if (p.match(/^\d/)) {
                    pd = p.replace(/,/g, ".");
                    break;
                }
            }
            if (pd <= 0) {
                alert("Cannot abbreviate weight.  No previous weight in this month's log.");
                return false;
            }
            if ((w == '.') || (w == ',')) {
                document.getElementById("w" + day).value = p;
            } else {
                var pn = Number(pd);
                if (unit == WEIGHT_STONE) {
                    
    var sf = p.match(/^(\d+)\s+(\d*[\.,]?\d*)$/);
    var stones, pounds;
    if (sf != null) {
        stones = Number(sf[1]);
        pounds = Number(sf[2].replace(/,/g, "."));
//alert("Previous st=" + stones + " lbs=" + pounds);
    }
//else { alert("Unable to parse previous stones value (" + p + ")"); }
    var nw = Number(w);
    if (pounds >= 10) {
        if (nw < 4) {
            if (w.match(/^[\.,]\d+$/)) {
                pounds = Math.floor(pounds) + nw;// alert("gonk 5");
            } else {
                pounds = ((Math.floor(pounds  / 10)) * 10) + nw;// alert("gonk 6");
            }
        } else {
            pounds = nw;// alert("gonk 2");
        }
    } else {
        if (w.match(/^[\.,]\d+$/)) {
            pounds = Math.floor(pounds) + nw;// alert("gonk 3");
        } else {
            pounds = nw;// alert("gonk 4");
        }
    }
//alert("New st=" + stones + " lbs=" + pounds);
    document.getElementById("w" + day).value = editWeight((stones * 14) + pounds, unit);

                } else {
                    if (w.match(/^[\.,]\d+$/)) {
                        document.getElementById("w" + day).value =
                            editWeight(Math.floor(pn) + Number(w), unit);
                    } else if (w.match(/^\d([\.,]\d*)?$/)) {
                        document.getElementById("w" + day).value =
                            editWeight(((Math.floor(pn  / 10)) * 10) + Number(w), unit);
                    }
//else { alert("Failed to parse (" + w + ")"); }
                }
            }
        }
        return true;
    }

    var plot;
    var plotChart;

    function getCanvas(imageID) {
        if (!plot) {
            var canvas = document.getElementById("canvas");
            plotChart = document.getElementById(imageID);
            var elementChain = plotChart;
            var offsetLeft = 0, offsetTop = 0;
            while (elementChain) {
                offsetLeft += elementChain.offsetLeft;
                offsetTop += elementChain.offsetTop;
                elementChain = elementChain.offsetParent;
            }
            canvas.style.width = plotChart.width + "px";
            canvas.style.height = plotChart.height + "px";
            canvas.style.left = offsetLeft + "px";
            canvas.style.top = offsetTop + "px";
            canvas.style.visibility = "visible";
            plot = new jsGraphics(canvas);
//alert("Create canvas");
        }
        return plot;
    }

    function resizeEvent(e) {
        var canvas = document.getElementById("canvas");
        var chart = plotChart;
        var elementChain = plotChart;
        var offsetLeft = 0, offsetTop = 0;
        while (elementChain) {
            offsetLeft += elementChain.offsetLeft;
            offsetTop += elementChain.offsetTop;
            elementChain = elementChain.offsetParent;
        }
        canvas.style.left = offsetLeft + "px";
        canvas.style.top = offsetTop + "px";
    }

    function setResizeEventHandle() {
        //  For competently-implemented and standards-compliant browsers
        if (document.implementation.hasFeature("Events", "2.0")) {
            this.addEventListener("resize", resizeEvent, false);
        //  For Exploder
        } else if (document.attachEvent) {
            this.attachEvent("onresize", resizeEvent);
        }
    }

    function changeWeight(day) {
        var n = Number(document.getElementById("md").getAttribute("value"));    // Number of days
        var t = Number(document.getElementById("t0").getAttribute("value"));    // Trend carry-forward
        var unit = Number(document.getElementById("du").getAttribute("value")); // Display unit
        var height = Number(document.getElementById("hgt").getAttribute("value")); // Height in centimetres
        decimalCharacter = document.getElementById("dc").getAttribute("value");

        if (!expandAbbreviatedWeight(day, unit)) {
            document.getElementById("w" + day).value = "";
            return;
        }

        var ckw = 0;
        if (document.getElementById("w" + day).value.match(/^\s*$/)) {
            document.getElementById("w" + day).value = "";
        } else {
            var ckw = parseWeight(document.getElementById("w" + day).value, unit);
            if (ckw < 0) {
                alert("Weight entry invalid.");
                resetFocus("w", day);
                return;
            }
        }

        countChange();

        
    /* Find the last non-blank weight entry in the log. */
    var nd = n;

    while ((nd > 0) && (!document.getElementById("w" + nd).value.match(/^\d/))) {
        nd--;
    }
    nd = Math.max(nd, day);

    /* If this is not the first day of the month, get the trend from
       the previous day's entry. */

    if (day > 1) {
        var lt = document.getElementById("t" + (day - 1)).firstChild.data;
        if (lt.match(/^\d/)) {
            t = parseWeight(lt, unit);
        } else {
            var jt = "", j, k;
            for (j = day - 2; j >= 1; j--) {
                jt = document.getElementById("t" + j).firstChild.data;
                if (jt.match(/^\d/)) {
                    break;
                }
            }
            if (j == 0) {
                jt = document.getElementById("t0").getAttribute("value");
            }
            if (jt != "" && jt != 0) {
                t = parseWeight(jt, unit);
                for (k = j + 1; k < day; k++) {
                    replaceText("t" + k, editWeight(t, unit));
                    document.getElementById("T" + k).setAttribute("value", t.toFixed(4));
                }
            }
        }
    }

    /* If this is the first day of the month, use the trend
       carry-forward as the previous trend value.  If no trend
       carry-forward is specified, simply use the current weight
       to start the trend. */

    if (t == 0) {
        t = parseWeight(document.getElementById("w" + day).value, unit);
    }


        
    if ((t > 0) && (ckw > 0) && ((Math.abs(t - ckw) / t) > 0.06)) {
        var deltad = -1, lastw = 0;
        for (var ld = day - 1; ld >= 1; ld--) {
            if (document.getElementById("w" + ld).value != "") {
                deltad = day - ld;
                lastw = parseWeight(document.getElementById("w" + ld).value, unit);
                break;
            }
        }
        if (deltad == -1) {
            deltad = day;
        }
//alert("deltad " + deltad + " lastw " + lastw);
        if (lastw > 0) {
            if (Math.abs(lastw - ckw) > Math.abs(t - ckw)) {
                lastw = t;
            }
        } else {
            var simt = t;
            for (var i = 1; i < deltad; i++) {
                simt = simt + (((t + (((ckw - t) * i) / deltad)) - simt) / 10);
            }
//alert("simt " + simt);
            lastw = simt;
        }
//alert("Adjusted lastw " + lastw);
        if ((Math.abs(ckw - lastw) / lastw) > 0.06) {
            if (!confirm("This weight is a " +
                (((ckw - lastw) * 100) / lastw).toFixed(1).replace(/\./, decimalCharacter) +
                "% change\u2014possibly incorrect.\n" +
                "Press OK to accept weight as entered, Cancel to correct.")) {
                resetFocus("w", day);
                return;
            }
        }
    }


        

/* ******

    var scaling = document.getElementById("sc").getAttribute("value").
            match(/^([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+)$/);
    for (var i = 1; i <= 7; i++) {
        scaling[i] = Number(scaling[i]);
    }

    for (var d = day; d < (nd - 1); d++) {
        var tfrom = document.getElementById("T" + (d + 1)).getAttribute("value"),
            tto = document.getElementById("T" + (d + 2)).getAttribute("value");
        if (tfrom.match(/^\d/) && tto.match(/^\d/)) {
            tfrom = Number(tfrom);
            tto = Number(tto);
            var plot = getCanvas("chart");
            var px1 = scaling[1] + (scaling[2] * (d));
            var py1 = scaling[3] - Math.floor(((tfrom - scaling[4]) * scaling[5]) / scaling[6]);
            var px2 = scaling[1] + (scaling[2] * (d + 1));
            var py2 = scaling[3] - Math.floor(((tto - scaling[4]) * scaling[5]) / scaling[6]);
            plot.setColor("#FFFF00");
            plot.drawLine(px1, py1, px2, py2);
            plot.paint();
        }
    }

****** */


        plotWeightOnChart(day, unit);

        
//alert("Change weight " + day + " " + t + "  (" + document.getElementById("w" + day).value + ") t = " + t);
    for (var i = day; i <= n; i++) {
        var w = document.getElementById("w" + i).value;
        if (w.match(/^\d/)) {
            if (t < 0) {
                t = parseWeight(w, unit);
            } else {
                t = t + ((parseWeight(w, unit) - t) / 10);
            }
            replaceText("t" + i, editWeight(t, unit));
            updateVariance("v" + i, parseWeight(w, unit) - t);
            document.getElementById("T" + i).setAttribute("value", t.toFixed(4));
        } else {
            replaceText("v" + i, "");
            if ((i <= nd) && (t > 0)) {
                replaceText("t" + i, editWeight(t, unit));
                document.getElementById("T" + i).setAttribute("value", t.toFixed(4));
            } else {
                replaceText("t" + i, "");
                document.getElementById("T" + i).setAttribute("value", "");
            }
        }
    }
    
/* ******

    for (var d = day; d < (n - 1); d++) {
        var tfrom = document.getElementById("T" + (d + 1)).getAttribute("value"),
            tto = document.getElementById("T" + (d + 2)).getAttribute("value");
        if (tfrom.match(/^\d/) && tto.match(/^\d/)) {
            tfrom = Number(tfrom);
            tto = Number(tto);
            var plot = getCanvas("chart");
            var px1 = scaling[1] + (scaling[2] * (d));
            var py1 = scaling[3] - Math.floor(((tfrom - scaling[4]) * scaling[5]) / scaling[6]);
            var px2 = scaling[1] + (scaling[2] * (d + 1));
            var py2 = scaling[3] - Math.floor(((tto - scaling[4]) * scaling[5]) / scaling[6]);
            plot.setColor("#FF0000");
            plot.drawLine(px1, py1, px2, py2);
            plot.paint();
        }
    }

****** */



        
    if (nd > 1) {
        var np = 0;
        fitStart();
        for (var i = 1; i <= nd; i++) {
            var w = document.getElementById("t" + i).firstChild.data;
            if (w.match(/^\d/)) {
                var nw = parseWeight(w, unit);
                if (nw > 0) {
                    fitAddPoint(nw);
                    np++;
                }
            }
        }

        var tslope = fitSlope();
        if (np < 2) {
            tslope = 0;
        }
        replaceText("delta_sign", tslope > 0 ? "gain" : "loss");
        replaceText("weekly_delta", Math.abs(tslope * 7).toFixed(2).replace(/\./, decimalCharacter));

        replaceText("calorie_sign", tslope > 0 ? "excess" : "deficit");
        replaceText("daily_calories", Math.round(Math.abs(tslope) * CALORIES_PER_WEIGHT_UNIT[unit]));
    }


        
    var tweight = 0, lweight = 0, nw = 0;

    for (var i = 1; i <= n; i++) {
        var w = document.getElementById("w" + i).value;
        if (w.match(/^\d/)) {
            lweight = parseWeight(document.getElementById("t" + i).firstChild.data, unit);
            tweight += lweight;
            nw++;
        }
    }

    if ((nw > 0) && (height > 0)) {
        tweight /= nw;
        tweight *= WEIGHT_CONVERSION[unit][WEIGHT_KILOGRAM];
        lweight *= WEIGHT_CONVERSION[unit][WEIGHT_KILOGRAM];
        height /= 100;
        height *= height;
        replaceText("mean_bmi", (tweight / height).toFixed(1).replace(/\./, decimalCharacter));
        replaceText("last_bmi", (lweight / height).toFixed(1).replace(/\./, decimalCharacter));
        document.getElementById("bmi").style.display = "inline";
    } else {
        document.getElementById("bmi").style.display = "none";
    }

    }

    function plotWeightOnChart(day, unit) {
        
    var scaling = document.getElementById("sc").getAttribute("value").
            match(/^([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+)$/);
    for (var i = 1; i <= 7; i++) {
        scaling[i] = Number(scaling[i]);
    }

        var dweight = parseWeight(document.getElementById("w" + day).value, unit);
        if ((dweight >= scaling[4]) && (dweight <= (scaling[4] + scaling[6]))) {
            var plot = getCanvas("chart");
            var px = scaling[1] + (scaling[2] * (day - 1));
            var py = scaling[3] - Math.floor(((dweight - scaling[4]) * scaling[5]) / scaling[6]);

            var sinkerSize = 4;

            //  Fill float/sinker with white or yellow, if it's flagged.

            plot.setColor(document.getElementById("f" + day).checked ? "#FFFF00" : "#FFFFFF");
            for (var j = -sinkerSize; j <= sinkerSize; j++) {
                var dx = Math.abs(j) - sinkerSize;

                plot.drawLine(px - dx, py + j, px + dx, py + j);
            }

            //  Trace the outline of the float/sinker in blue

            plot.setColor("#0000FF");
            plot.drawLine(px - sinkerSize, py, px, py - sinkerSize);
            plot.drawLine(px, py - sinkerSize, px + sinkerSize, py);
            plot.drawLine(px + sinkerSize, py, px, py + sinkerSize);
            plot.drawLine(px, py + sinkerSize, px - sinkerSize, py);

            plot.paint();
        }
    }

    function changeRung(day) {
        if (document.getElementById("r" + day).value.match(/^\s*[\.,\+\-]\s*$/)) {
            var r = 0;
            for (var i = day - 1; i >= 1; i--) {
                r = document.getElementById("r" + i).value;
                if (r.match(/^\d/)) {
                    break;
                }
                r = Number(r);
            }
            if (r <= 0) {
                alert("Cannot copy rung.  No previous rung in this month's log.");
                document.getElementById("r" + day).value = "";
                return;
            }
            if (document.getElementById("r" + day).value.match(/^\s*[\+]\s*$/)) {
                r++;
            } else if (document.getElementById("r" + day).value.match(/^\s*[\-]\s*$/)) {
                r--;
            }
            document.getElementById("r" + day).value = r;
        }
        if (document.getElementById("r" + day).value.match(/^\s*$/)) {
            document.getElementById("r" + day).value = "";
        } else {
            var r = Math.floor(Number(document.getElementById("r" + day).value));
            if (isNaN(r) || (r < 1) || (r > 48)) {
                alert("Rung value invalid.  Must be integer between 1 and 48.");
                resetFocus("r", day);
            } else {
                document.getElementById("r" + day).value = r;
                
    
    var scaling = document.getElementById("sc").getAttribute("value").
            match(/^([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+)$/);
    for (var i = 1; i <= 7; i++) {
        scaling[i] = Number(scaling[i]);
    }


    if ((r >= 1) && (r <= scaling[7])) {
        var n = Number(document.getElementById("md").getAttribute("value")); // Days in month

        var plot = getCanvas("chart");
        plot.setColor("#0000FF");

        var cx = scaling[1] + (scaling[2] * (day - 1)),
            cy = scaling[3] - Math.floor(((r - 1) * scaling[5]) / scaling[7]);

        if (day == n) {
            var lx = scaling[1] + (scaling[2] * (day - 2));
            if (document.getElementById("r" + (day - 1)).value != "") {
                //  Yesterday defined--plot from yesterday to today
                var ly = scaling[3] - Math.floor(((Number(document.getElementById("r" + (day - 1)).value) - 1) * scaling[5]) / scaling[7]);
                plot.drawLine(lx, ly, cx, cy);
            } else {
                //  Yesterday not defined--plot a flat line from yesterday to today
                plot.drawLine(lx, cy, cx, cy);
            }
        } else {
            if ((day > 1) && (document.getElementById("r" + (day - 1)).value != "")) {
                //  Yesterday defined--plot from yesterday to today
                var lx = scaling[1] + (scaling[2] * (day - 2)),
                    ly = scaling[3] - Math.floor(((Number(document.getElementById("r" + (day - 1)).value) - 1) * scaling[5]) / scaling[7]);
                plot.drawLine(lx, ly, cx, cy);
            } else {
                if (document.getElementById("r" + (day + 1)).value != "") {
                    //  Tomorrow defined--plot from today to tomorrow
                    var nx = scaling[1] + (scaling[2] * day),
                        ny = scaling[3] - Math.floor(((Number(document.getElementById("r" + (day + 1)).value) - 1) * scaling[5]) / scaling[7]);
                    plot.drawLine(cx, cy, nx, ny);
                } else {
                    //  Tomorrow not defined--plot a flat line from today to tomorrow
                    var nx = scaling[1] + (scaling[2] * day);
                    plot.drawLine(cx, cy, nx, cy);
                }
            }
        }

        plot.paint();
    }

            }
        }
        countChange();
    }

    function changeComment(day) {
        if ((document.getElementById("c" + day).value == ".") ||
            (document.getElementById("c" + day).value == ",")) {
            var r = "";
            for (var i = day - 1; i >= 1; i--) {
                r = document.getElementById("c" + i).value;
                if (!r.match(/^\s*$/)) {
                    break;
                }
            }
            if (r == "") {
                alert("Cannot copy comment.  No previous comment in this month's log.");
                document.getElementById("c" + day).value = "";
                return;
            }
            document.getElementById("c" + day).value = r;
        }
        countChange();
    }

    var calc_calorie_balance, calc_energy_unit,
        calc_start_weight, calc_weight_unit,
        calc_goal_weight, calc_weight_change,
        calc_weight_week, calc_weeks, calc_months,
        calc_start_date, calc_end_date;


    function loadDietCalcFields() {
        decimalCharacter = document.getElementById("dc").getAttribute("value");
        calc_energy_unit = document.getElementById("calc_energy_unit").selectedIndex;
        calc_calorie_balance = Number(document.getElementById("calc_calorie_balance").value.replace(/,/g, ".")) *
            CALORIES_PER_ENERGY_UNIT[calc_energy_unit];
        calc_weight_unit = document.getElementById("calc_weight_unit").selectedIndex;
        calc_start_weight =
            parseWeight(document.getElementById("calc_start_weight").value, calc_weight_unit);
        calc_goal_weight =
            parseWeight(document.getElementById("calc_goal_weight").value, calc_weight_unit);
        calc_weight_change = parseSignedWeight(document.getElementById("calc_weight_change").value, calc_weight_unit);
        calc_weight_week =
            parseSignedWeight(document.getElementById("calc_weight_week").value, calc_weight_unit);
        calc_weeks = Number(document.getElementById("calc_weeks").value);
        calc_months = Number(document.getElementById("calc_months").value);
        calc_start_date = get_selected_date("from");
        calc_end_date = get_selected_date("to");
    }

    function dietCalcRecalculate() {
        calc_weight_change = calc_goal_weight - calc_start_weight;
        calc_weight_week = (calc_calorie_balance * 7) / CALORIES_PER_WEIGHT_UNIT[calc_weight_unit];
        calc_weeks = Math.round(calc_weight_change / calc_weight_week);
        calc_months = Math.round(((calc_weight_change / calc_weight_week) * 7.0) / 30.44);
        calc_end_date = calc_start_date + (calc_weeks * 7 * 24 * 60 * 60 * 1000);

        //  Update the form fields with the new values

        document.getElementById("calc_calorie_balance").value = Math.round(calc_calorie_balance /
            CALORIES_PER_ENERGY_UNIT[document.getElementById("calc_energy_unit").selectedIndex]);
        document.getElementById("calc_start_weight").value =
            editWeight(calc_start_weight, calc_weight_unit);
        document.getElementById("calc_goal_weight").value =
            editWeight(calc_goal_weight, calc_weight_unit);
        document.getElementById("calc_weight_change").value =
            editWeight(calc_weight_change, calc_weight_unit);
        document.getElementById("calc_weight_week").value =
            editWeight(calc_weight_week, calc_weight_unit);
        document.getElementById("calc_weeks").value = calc_weeks;
        document.getElementById("calc_months").value = calc_months;
        set_date_selection("from", calc_start_date);
        set_date_selection("to", calc_end_date);

        if (calc_end_date <= calc_start_date) {
            document.getElementById("end_date").style.display = "none";
            document.getElementById("endless_date").style.display = "inline";
        } else {
            document.getElementById("end_date").style.display = "inline";
            document.getElementById("endless_date").style.display = "none";
        }

        countChange();
    }

    function set_date_selection(which, ms) {
        var date = new Date(ms);
        var year = date.getUTCFullYear(),
            month = date.getUTCMonth(),
            day = date.getUTCDate();

        var i;
        for (i = 0; i < document.getElementById(which + "_y").length; i++) {
            if (year == Number(document.getElementById(which + "_y").options[i].value)) {
                document.getElementById(which + "_y").selectedIndex = i;
                i = -1;
                break;
            }
        }
        if (i != -1) {
//alert("Added year " + year + " to " + which + " selection");
            document.getElementById(which + "_y").options[document.getElementById(which + "_y").length] =
                new Option(year, year);
            document.getElementById(which + "_y").selectedIndex = document.getElementById(which + "_y").length - 1;
        }
        document.getElementById(which + "_m").selectedIndex = month;
        document.getElementById(which + "_d").selectedIndex = day - 1;
    }

    function change_calc_calorie_balance() {
        loadDietCalcFields();
//alert("cccb " + calc_calorie_balance);
        dietCalcRecalculate();
    }

    function change_calc_energy_unit() {
        var old_calc_energy_unit = calc_energy_unit;
        loadDietCalcFields();
        calc_calorie_balance *= ENERGY_CONVERSION[old_calc_energy_unit][calc_energy_unit];
        dietCalcRecalculate();
    }

    function change_calc_start_weight() {
        loadDietCalcFields();
        if (calc_start_weight > 0) {
            dietCalcRecalculate();
        } else {
            alert("Invalid initial weight.");
            resetFocus("calc_start_weight");
        }
    }

    function change_calc_weight_unit() {
        var old_calc_weight_unit = calc_weight_unit;
        loadDietCalcFields();
        var new_calc_weight_unit = calc_weight_unit;
        calc_weight_unit = old_calc_weight_unit;
        calc_start_weight =
            parseWeight(document.getElementById("calc_start_weight").value, calc_weight_unit);
        calc_goal_weight =
            parseWeight(document.getElementById("calc_goal_weight").value, calc_weight_unit);
        calc_weight_unit = new_calc_weight_unit;
        calc_start_weight *= WEIGHT_CONVERSION[old_calc_weight_unit][calc_weight_unit];
        calc_goal_weight *= WEIGHT_CONVERSION[old_calc_weight_unit][calc_weight_unit];
        dietCalcRecalculate();
    }

    function change_calc_goal_weight() {
        loadDietCalcFields();
        if (calc_goal_weight > 0) {
            dietCalcRecalculate();
        } else {
            alert("Invalid goal weight.");
            resetFocus("calc_goal_weight");
        }
    }

    function change_calc_weight_change() {
        loadDietCalcFields();
        calc_goal_weight = calc_start_weight + calc_weight_change;
        dietCalcRecalculate();

    }

    function change_calc_weight_week() {
        loadDietCalcFields();
        calc_calorie_balance = calc_weight_week * (CALORIES_PER_WEIGHT_UNIT[calc_weight_unit] / 7);
//alert(calc_calorie_balance);
        dietCalcRecalculate();
    }

    function change_calc_weeks() {
        loadDietCalcFields();
        if (calc_weeks > 0) {
            calc_calorie_balance = Math.round(((calc_weight_change / calc_weeks) *
                (CALORIES_PER_WEIGHT_UNIT[calc_weight_unit] / 7)));
            dietCalcRecalculate();
        } else {
            alert("Weeks duration must be greater than zero.");
            resetFocus("calc_weeks");
        }
    }

    function change_calc_months() {
        loadDietCalcFields();
        if (calc_months > 0) {
            calc_calorie_balance = Math.round(((calc_weight_change / calc_months) *
                (CALORIES_PER_WEIGHT_UNIT[calc_weight_unit] / 30.44)));
            dietCalcRecalculate();
        } else {
            alert("Months duration must be greater than zero.");
            resetFocus("calc_months");
        }
    }

    function change_from_date() {
        calc_start_date = get_selected_date("from");
        dietCalcRecalculate();
    }

    function change_from_y() {
        change_from_date();
    }

    function change_from_m() {
        change_from_date();
    }

    function change_from_d() {
        change_from_date();
    }

    function get_selected_date(which) {
        var year = document.getElementById(which + "_y").options[document.getElementById(which + "_y").selectedIndex].text,
            month = document.getElementById(which + "_m").selectedIndex,
            day = document.getElementById(which + "_d").selectedIndex + 1;
        return Date.UTC(year, month, day);

    }

    function change_to_date() {
        calc_end_date = get_selected_date("to");
        if (calc_end_date > calc_start_date) {
            calc_calorie_balance = Math.round((calc_weight_change /
                ((calc_end_date - calc_start_date) / (24 * 60 * 60 * 1000))) *
                CALORIES_PER_WEIGHT_UNIT[calc_weight_unit]);
        } else {
            alert("End date must be after start date.");
            resetFocus("to_y");
        }
        dietCalcRecalculate();
    }
    function change_to_y() {
        change_to_date();
    }

    function change_to_m() {
        change_to_date();
    }

    function change_to_d() {
        change_to_date();
    }

    function change_calc_plot_plan() {
        countChange();
    }

    function validateFeedback() {
        if (document.getElementById("category").selectedIndex <= 0) {
            alert("Please choose a category for your feedback message.");
            return false;
        }
        return true;
    }

    function resetFocus(fieldname, day) {
        if (arguments.length < 2) {
            day = "";
        }
        setTimeout("document.getElementById(\"" + fieldname + day + "\").focus()", 1);
    }

    /*
        externalLinks  --  Emulate "target=" in XHTML 1.0 Strict <a> tags

        http://www.sitepoint.com/article/standards-compliant-world

        Modified by John Walker to only extract and modify links with
        rel="Target:<frame>" and extract the frame name from that
        specification. */

    function externalLinks() {
        if (!document.getElementsByTagName) {
            return;
        }
        var anchors = document.getElementsByTagName("a");
        for (var i = 0; i < anchors.length; i++) {
            var anchor = anchors[i], target;
            if (anchor.getAttribute("href") &&
                anchor.getAttribute("rel") &&
                anchor.getAttribute("rel").match(/^Target:/)) {
                target = anchor.getAttribute("rel").match(/(^Target:)(\w+$)/);
                anchor.target = target[2];
            }
        }
    }

    function determineTimeZoneOffset() {
        if (document.getElementById && document.getElementById("tzoffset")) {
            document.getElementById("tzoffset").value = (new Date()).getTimezoneOffset();
        }
    }

    function canonicalNumber(value, places, decimal) {
        var v = value.toFixed(places);

        if (arguments.length < 3) {
            decimal = '.';
        }
        v = v.replace(/0+$/, "");
        v = v.replace(/\.$/, "");
        v = v.replace(/\./, decimal);
        return v;
    }

    function height_changed_cm() {
        var thisform = document.getElementById("Hdiet_newacct");
        var cm = thisform.HDiet_height_cm.value;
        cm = cm.replace(/,/, ".");
        if (cm > 244) {
            if (!confirm("That's awfully tall (" + cm + " centimetres).  Are you sure?")) {
                thisform.HDiet_height_cm.focus();
                thisform.HDiet_height_cm.select();
                return false;
            }
        }
         if (cm < 122) {
            if (!confirm("That's awfully short (" + cm + " centimetres).  Are you sure?")) {
                thisform.HDiet_height_cm.focus();
                thisform.HDiet_height_cm.select();
                return false;
            }
       }
        var inches = cm / 2.54;
        thisform.HDiet_height_ft.value = Math.floor(inches / 12);
        thisform.HDiet_height_in.value =
            canonicalNumber(inches % 12, 1, thisform.decimal_character.value);
    }

    function height_changed_ft() {
        var thisform = document.getElementById("Hdiet_newacct");
        var ft = thisform.HDiet_height_ft.value;
        if (ft > 7) {
            if (!confirm("That's awfully tall (" + ft + " feet).  Are you sure?")) {
                thisform.HDiet_height_ft.focus();
                thisform.HDiet_height_ft.select();
                return false;
            }
        }
         if (ft < 4) {
            if (!confirm("That's awfully short (" + ft + " feet).  Are you sure?")) {
                thisform.HDiet_height_ft.focus();
                thisform.HDiet_height_ft.select();
                return false;
            }
        }
        var cm = ft * 2.54 * 12;
        if (thisform.HDiet_height_in.value != '') {
            cm += thisform.HDiet_height_in.value * 2.54;
        }
        thisform.HDiet_height_cm.value =
            canonicalNumber(cm, 1, thisform.decimal_character.value);;
    }

    function height_changed_in() {
        var thisform = document.getElementById("Hdiet_newacct");
        var inches = thisform.HDiet_height_in.value;
        inches = inches.replace(/,/, ".");
        if (inches > 12) {
            if (inches > 7 * 12) {
                if (!confirm("That's awfully tall (" + inches + " inches).  Are you sure?")) {
                    thisform.HDiet_height_in.focus();
                    thisform.HDiet_height_in.select();
                    return false;
                }
            }
             if (inches < 4 * 12) {
                if (!confirm("That's awfully short (" + inches + " inches).  Are you sure?")) {
                    thisform.HDiet_height_in.focus();
                    thisform.HDiet_height_in.select();
                    return false;
                }
           }

            var feet = Math.floor(inches / 12);
            thisform.HDiet_height_ft.value = feet;
            inches -= feet * 12;
            thisform.HDiet_height_in.value = inches;
        }
        var cm = inches * 2.54;
        if (thisform.HDiet_height_ft.value != '') {
            cm += thisform.HDiet_height_ft.value * 2.54 * 12;
        }
        thisform.HDiet_height_cm.value =
            canonicalNumber(cm, 1, thisform.decimal_character.value);
    }

    var logunit_spec = -1, dispunit_spec = -1;

    function set_logunit(t) {
        if (dispunit_spec < 0) {
            var newu = t.value;
            document.getElementById("HDiet_dunit_" +
                WEIGHT_ABBREVIATIONS[newu]).checked = true;
        }
        logunit_spec = newu;
    }

    function set_dispunit(t) {
        if (logunit_spec < 0) {
            var newu = t.value;
            document.getElementById("HDiet_wunit_" +
                WEIGHT_ABBREVIATIONS[newu]).checked = true;
        }
        dispunit_spec = newu;
    }

    function replaceText(id, newtext) {
        var n = document.getElementById(id);
        n.replaceChild(document.createTextNode(newtext), n.firstChild);
    }

    function updateVariance(id, newvar) {
        var n = document.getElementById(id);
        var fn = Math.abs(newvar).toFixed(1).replace(/\./, decimalCharacter);
        var svar = ((fn == 0) ? "" :
            ((newvar > 0) ? "+" : U_MINUS_SIGN)) + fn;
        n.replaceChild(document.createTextNode(svar), n.firstChild);
        n.setAttribute('class', (fn == 0) ? "bk" :
            (newvar < 0) ? 'g' : 'r');
    }

    function updateFlag(day) {
        var unit = Number(document.getElementById("du").getAttribute("value"));
        plotWeightOnChart(day, unit);

        var ndays = document.getElementById("md").getAttribute("value");
        var i, nflagged = 0;
        for (i = 1; i <= ndays; i++) {
            if (document.getElementById("f" + i).checked) {
                nflagged++;
            }
        }
        var fracflagged = Math.round((nflagged * 100) / ndays);
        if (fracflagged > 0) {
            replaceText("percent_flagged", fracflagged + "%");
            document.getElementById("fracf").style.display = "inline";
        } else {
            document.getElementById("fracf").style.display = "none";
        }
        countChange();
    }

    function passwordStrength(s) {
        
    var characterFrequency = new Array (
        0.10696, 0.00081822, 0.0023291, 4.3716e-05, 0.00015954, 1.8698e-05,
        8.4113e-05, 0.0030053, 0.00047366, 0.00047334, 5.0773e-05, 4.7613e-05,
        0.0074841, 0.003832, 0.0073566, 0.0022768, 0.0006086, 0.0010785,
        0.00065979, 0.00050631, 0.00045059, 0.00044005, 0.00038765,
        0.00035741, 0.00034319, 0.00035236, 0.00050331, 0.0013616, 0.005661,
        0.0012761, 0.0055853, 0.00077171, 0.00013994, 0.0035894, 0.0013236,
        0.0019242, 0.0014263, 0.003019, 0.00099098, 0.0010051, 0.001466,
        0.0034202, 0.00031154, 0.00053323, 0.0018927, 0.0016076, 0.0019353,
        0.0020567, 0.0012778, 0.00019367, 0.0018611, 0.0029033, 0.0026777,
        0.0010777, 0.00044205, 0.0012584, 7.0946e-05, 0.00058568, 0.00012246,
        0.00020457, 0.00019619, 0.00020383, 7.005e-06, 0.00018455, 2.4702e-05,
        0.065786, 0.014786, 0.027696, 0.029905, 0.097183, 0.011098, 0.016708,
        0.027406, 0.062681, 0.0013139, 0.0057647, 0.04161, 0.023039, 0.058548,
        0.056328, 0.020771, 0.0023996, 0.054953, 0.057549, 0.055857, 0.031333,
        0.008424, 0.0082229, 0.0021771, 0.014088, 0.0025955, 0.00022901,
        9.1645e-05, 0.00022885, 5.7936e-06, 0, 0.00014447, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0.00022864, 0, 0, 0, 0, 6.1623e-06, 0, 0, 0, 0, 0, 0, 0, 0,
        5.2669e-08, 0, 0.00022595, 0, 0, 0, 5.2406e-05, 1.4747e-06,
        2.1068e-07, 1.5801e-07, 0, 1.0007e-06, 0, 0, 5.2669e-07, 8.9538e-07,
        5.7568e-05, 6.847e-07, 1.5801e-07, 5.2669e-07, 1.5801e-07, 4.2136e-07,
        1.5801e-07, 0, 0, 1.5801e-07, 1.5801e-07, 1.9172e-05, 0, 4.2136e-07,
        0, 0, 8.9538e-07, 1.5801e-07, 1.5801e-07, 5.7936e-06, 0, 0,
        0.00014258, 0.0004153, 0.00039244, 6.3467e-05, 0, 0.00017786, 0, 0,
        3.5815e-05, 0.00024918, 0.0017644, 0.00013225, 3.3708e-06, 1.5801e-07,
        0.0001953, 4.7455e-05, 1.4905e-05, 0, 7.5107e-05, 1.3641e-05,
        0.00011571, 2.2279e-05, 0, 0.00010207, 0, 0, 3.0127e-05, 3.039e-05,
        4.282e-05, 0.00026688, 0, 0, 0
    );


        var pprob = 1.0;

        
    //  The string "password" and other bozo classics
    s = s.replace(/password|secret|qwerty|cookie|loveyou|/ig, "");

    //  Consecutive identical characters
    s = s.replace(/(.)\1+/g, "$1");

    //  Three or more characters in code point order or decending order
    for (i = 0; i < s.length - 2; i++) {
        if (((s.charCodeAt(i) == (s.charCodeAt(i + 1) - 1)) &&
             (s.charCodeAt(i + 1) == (s.charCodeAt(i + 2) - 1))) ||
             ((s.charCodeAt(i) == (s.charCodeAt(i + 1) + 1)) &&
             (s.charCodeAt(i + 1) == (s.charCodeAt(i + 2) + 1)))
            ) {
            s = s.substring(0, i) + s.substring(i + 1);
            i = 0;
        }
    }


        for (i = 0; i < s.length; i++) {
            var c = s.charCodeAt(i), p;
            if (c > 0xFF) {
                p = (1.0 / 65536.0) * ((psLog2(c) - 8) / 16);
            } else {
                p = characterFrequency[(c < 128) ? (c - 32) : (c - 65)];
                if (p == 0) {
                    p = 1.0e-7;
                }
            }
            pprob *= p;
        }
        return 1 / pprob;
    }

    function showPasswordStrength() {
        var thisform = document.getElementById("Hdiet_newacct");
        var ps = passwordStrength(thisform.HDiet_password.value);
        thisform.HDiet_password_strength.value =
            (thisform.HDiet_password.value.length < 6) ? 0 :
        Math.round(Math.min(Math.max(psLog10(ps) - 9, 1), 10));
    }

    function checkPasswordMatch() {
        var thisform = document.getElementById("Hdiet_newacct");
        thisform.HDiet_password_match.checked =
            thisform.HDiet_password.value == thisform.HDiet_rpassword.value;
    }

    function psLog2(x) {
        return Math.LOG2E * Math.log(x);
    }

    function psLog10(x) {
        return Math.LOG10E * Math.log(x);
    }

function dump()
{
    var t = "", i;

    for (i = 0; i < arguments.length; i += 2) {
        if (t.length > 0) {
            t += ", ";
        }
        t += arguments[i] + " = " + arguments[i + 1];
    }
    document.getElementById("debugging_console").log.value += t + "\n";
}
