<!DOCTYPE html>
<html data-color-mode="auto" data-light-theme="dark_dimmed" data-dark-theme="dark_high_contrast" data-a11y-animated-images="system" data-lt-installed="true" class="js-focus-visible" data-js-focus-visible="" data-turbo-loaded="" lang="en"><script type="text/javascript">try {
(function injectPageScriptAPI(scriptName, shouldOverrideWebSocket, shouldOverrideWebRTC, isInjected) { 

    'use strict';

    /**
     * If script have been injected into a frame via contentWindow then we can simply take the copy of messageChannel left for us by parent document
     * Otherwise creates new message channel that sends a message to the content-script to check if request should be allowed or not.
     */
    var messageChannel = isInjected ? window[scriptName] : (function () {

        // Save original postMessage and addEventListener functions to prevent webpage from tampering both.
        var postMessage = window.postMessage;
        var addEventListener = window.addEventListener;

        // Current request ID (incremented every time we send a new message)
        var currentRequestId = 0;
        var requestsMap = {};

        /**
         * Handles messages sent from the content script back to the page script.
         *
         * @param event Event with necessary data
         */
        var onMessageReceived = function (event) {

            if (!event.data || !event.data.direction || event.data.direction !== "to-page-script@abu") {
                return;
            }

            var requestData = requestsMap[event.data.requestId];
            if (requestData) {
                var wrapper = requestData.wrapper;
                requestData.onResponseReceived(wrapper, event.data.block);
                delete requestsMap[event.data.requestId];
            }
        };

        /**
         * @param url                The URL to which wrapped object is willing to connect
         * @param requestType        Request type ( WEBSOCKET or WEBRTC)
         * @param wrapper            WebSocket wrapper instance
         * @param onResponseReceived Called when response is received
         */
        var sendMessage = function (url, requestType, wrapper, onResponseReceived) {

            if (currentRequestId === 0) {
                // Subscribe to response when this method is called for the first time
                addEventListener.call(window, "message", onMessageReceived, false);
            }

            var requestId = ++currentRequestId;
            requestsMap[requestId] = {
                wrapper: wrapper,
                onResponseReceived: onResponseReceived
            };

            var message = {
                requestId: requestId,
                direction: 'from-page-script@abu',
                elementUrl: url,
                documentUrl: document.URL,
                requestType: requestType
            };

            // Send a message to the background page to check if the request should be blocked
            postMessage.call(window, message, "*");
        };

        return {
            sendMessage: sendMessage
        };

    })();

    /*
     * In some case Chrome won't run content scripts inside frames.
     * So we have to intercept access to contentWindow/contentDocument and manually inject wrapper script into this context
     *
     * Based on: https://github.com/adblockplus/adblockpluschrome/commit/1aabfb3346dc0821c52dd9e97f7d61b8c99cd707
     */
    var injectedToString = Function.prototype.toString.bind(injectPageScriptAPI);

    var injectedFramesAdd;
    var injectedFramesHas;
    if (window.WeakSet instanceof Function) {
        var injectedFrames = new WeakSet();
        injectedFramesAdd = WeakSet.prototype.add.bind(injectedFrames);
        injectedFramesHas = WeakSet.prototype.has.bind(injectedFrames);
    } else {
        var frames = [];
        injectedFramesAdd = function (el) {
            if (frames.indexOf(el) < 0) {
                frames.push(el);
            }
        };
        injectedFramesHas = function (el) {
            return frames.indexOf(el) >= 0;
        };
    }

    /**
     * Injects wrapper's script into passed window
     * @param contentWindow Frame's content window
     */
    function injectPageScriptAPIInWindow(contentWindow) {
        try {
            if (contentWindow && !injectedFramesHas(contentWindow)) {
                injectedFramesAdd(contentWindow);
                contentWindow[scriptName] = messageChannel; // Left message channel for the injected script
                var args = "'" + scriptName + "', " + shouldOverrideWebSocket + ", " + shouldOverrideWebRTC + ", true";
                contentWindow.eval("(" + injectedToString() + ")(" + args + ");");
                delete contentWindow[scriptName];
            }
        } catch (e) {
        }
    }

    /**
     * Overrides access to contentWindow/contentDocument for the passed HTML element's interface (iframe, frame, object)
     * If the content of one of these objects is requested we will inject our wrapper script.
     * @param iface HTML element's interface
     */
    function overrideContentAccess(iface) {

        var contentWindowDescriptor = Object.getOwnPropertyDescriptor(iface.prototype, "contentWindow");
        var contentDocumentDescriptor = Object.getOwnPropertyDescriptor(iface.prototype, "contentDocument");

        // Apparently in HTMLObjectElement.prototype.contentWindow does not exist
        // in older versions of Chrome such as 42.
        if (!contentWindowDescriptor) {
            return;
        }

        var getContentWindow = Function.prototype.call.bind(contentWindowDescriptor.get);
        var getContentDocument = Function.prototype.call.bind(contentDocumentDescriptor.get);

        contentWindowDescriptor.get = function () {
            var contentWindow = getContentWindow(this);
            injectPageScriptAPIInWindow(contentWindow);
            return contentWindow;
        };
        contentDocumentDescriptor.get = function () {
            injectPageScriptAPIInWindow(getContentWindow(this));
            return getContentDocument(this);
        };

        Object.defineProperty(iface.prototype, "contentWindow", contentWindowDescriptor);
        Object.defineProperty(iface.prototype, "contentDocument", contentDocumentDescriptor);
    }

    var interfaces = [HTMLFrameElement, HTMLIFrameElement, HTMLObjectElement];
    for (var i = 0; i < interfaces.length; i++) {
        overrideContentAccess(interfaces[i]);
    }

    /**
     * Defines properties in destination object
     * @param src Source object
     * @param dest Destination object
     * @param properties Properties to copy
     */
    var copyProperties = function (src, dest, properties) {
        for (var i = 0; i < properties.length; i++) {
            var prop = properties[i];
            var descriptor = Object.getOwnPropertyDescriptor(src, prop);
            // Passed property may be undefined
            if (descriptor) {
                Object.defineProperty(dest, prop, descriptor);
            }
        }
    };

    /**
     * Check request by sending message to content script
     * @param url URL to block
     * @param type Request type
     * @param callback Result callback
     */
    var checkRequest = function (url, type, callback) {
        messageChannel.sendMessage(url, type, this, function (wrapper, blockConnection) {
            callback(blockConnection);
        });
    };

    /**
     * The function overrides window.WebSocket with our wrapper, that will check url with filters through messaging with content-script.
     *
     * IMPORTANT NOTE:
     * This function is first loaded as a content script. The only purpose of it is to call
     * the "toString" method and use resulting string as a text content for injected script.
     */
    var overrideWebSocket = function () { 

        if (!(window.WebSocket instanceof Function)) {
            return;
        }

        /**
         * WebSocket wrapper implementation.
         * https://github.com/AdguardTeam/AdguardBrowserExtension/issues/349
         *
         * Based on:
         * https://github.com/adblockplus/adblockpluschrome/commit/457a336ee55a433217c3ffe5d363e5c6980f26f4
         */

        /**
         * As far as possible we must track everything we use that could be sabotaged by the website later in order to circumvent us.
         */
        var RealWebSocket = WebSocket;
        var closeWebSocket = Function.prototype.call.bind(RealWebSocket.prototype.close);

        function WrappedWebSocket(url, protocols) {
            // Throw correct exceptions if the constructor is used improperly.
            if (!(this instanceof WrappedWebSocket)) {
                return RealWebSocket();
            }
            if (arguments.length < 1) {
                return new RealWebSocket();
            }

            var websocket = new RealWebSocket(url, protocols);

            // This is the key point: checking if this WS should be blocked or not
            // Don't forget that the type of 'websocket.url' is String, but 'url 'parameter might have another type.
            checkRequest(websocket.url, 'WEBSOCKET', function (blocked) {
                if (blocked) {
                    closeWebSocket(websocket);
                }
            });

            return websocket;
        }

        // https://github.com/AdguardTeam/AdguardBrowserExtension/issues/488
        WrappedWebSocket.prototype = RealWebSocket.prototype;
        window.WebSocket = WrappedWebSocket.bind();

        copyProperties(RealWebSocket, WebSocket, ["CONNECTING", "OPEN", "CLOSING", "CLOSED", "name", "prototype"]);

        RealWebSocket.prototype.constructor = WebSocket;

    };

    /**
     * The function overrides window.RTCPeerConnection with our wrapper, that will check ice servers URLs with filters through messaging with content-script.
     *
     * IMPORTANT NOTE:
     * This function is first loaded as a content script. The only purpose of it is to call
     * the "toString" method and use resulting string as a text content for injected script.
     */
    var overrideWebRTC = function () { 


        if (!(window.RTCPeerConnection instanceof Function) &&
            !(window.webkitRTCPeerConnection instanceof Function)) {
            return;
        }

        /**
         * RTCPeerConnection wrapper implementation.
         * https://github.com/AdguardTeam/AdguardBrowserExtension/issues/588
         *
         * Based on:
         * https://github.com/adblockplus/adblockpluschrome/commit/af0585137be19011eace1cf68bf61eed2e6db974
         *
         * Chromium webRequest API doesn't allow the blocking of WebRTC connections
         * https://bugs.chromium.org/p/chromium/issues/detail?id=707683
         */

        var RealRTCPeerConnection = window.RTCPeerConnection || window.webkitRTCPeerConnection;
        var closeRTCPeerConnection = Function.prototype.call.bind(RealRTCPeerConnection.prototype.close);

        var RealArray = Array;
        var RealString = String;
        var createObject = Object.create;
        var defineProperty = Object.defineProperty;

        /**
         * Convert passed url to string
         * @param url URL
         * @returns {string}
         */
        function urlToString(url) {
            if (typeof url !== "undefined") {
                return RealString(url);
            }
        }

        /**
         * Creates new immutable array from original with some transform function
         * @param original
         * @param transform
         * @returns {*}
         */
        function safeCopyArray(original, transform) {

            if (original === null || typeof original !== "object") {
                return original;
            }

            var immutable = RealArray(original.length);
            for (var i = 0; i < immutable.length; i++) {
                defineProperty(immutable, i, {
                    configurable: false, enumerable: false, writable: false,
                    value: transform(original[i])
                });
            }
            defineProperty(immutable, "length", {
                configurable: false, enumerable: false, writable: false,
                value: immutable.length
            });
            return immutable;
        }

        /**
         * Protect configuration from mutations
         * @param configuration RTCPeerConnection configuration object
         * @returns {*}
         */
        function protectConfiguration(configuration) {

            if (configuration === null || typeof configuration !== "object") {
                return configuration;
            }

            var iceServers = safeCopyArray(
                configuration.iceServers,
                function (iceServer) {

                    var url = iceServer.url;
                    var urls = iceServer.urls;

                    // RTCPeerConnection doesn't iterate through pseudo Arrays of urls.
                    if (typeof urls !== "undefined" && !(urls instanceof RealArray)) {
                        urls = [urls];
                    }

                    return createObject(iceServer, {
                        url: {
                            configurable: false, enumerable: false, writable: false,
                            value: urlToString(url)
                        },
                        urls: {
                            configurable: false, enumerable: false, writable: false,
                            value: safeCopyArray(urls, urlToString)
                        }
                    });
                }
            );

            return createObject(configuration, {
                iceServers: {
                    configurable: false, enumerable: false, writable: false,
                    value: iceServers
                }
            });
        }

        /**
         * Check WebRTC connection's URL and close if it's blocked by rule
         * @param connection Connection
         * @param url URL to check
         */
        function checkWebRTCRequest(connection, url) {
            checkRequest(url, 'WEBRTC', function (blocked) {
                if (blocked) {
                    try {
                        closeRTCPeerConnection(connection);
                    } catch (e) {
                        // Ignore exceptions
                    }
                }
            });
        }

        /**
         * Check each URL of ice server in configuration for blocking.
         *
         * @param connection RTCPeerConnection
         * @param configuration Configuration for RTCPeerConnection
         * https://developer.mozilla.org/en-US/docs/Web/API/RTCConfiguration
         */
        function checkConfiguration(connection, configuration) {

            if (!configuration || !configuration.iceServers) {
                return;
            }

            var iceServers = configuration.iceServers;
            for (var i = 0; i < iceServers.length; i++) {

                var iceServer = iceServers[i];
                if (!iceServer) {
                    continue;
                }

                if (iceServer.url) {
                    checkWebRTCRequest(connection, iceServer.url);
                }

                if (iceServer.urls) {
                    for (var j = 0; j < iceServer.urls.length; j++) {
                        checkWebRTCRequest(connection, iceServer.urls[j]);
                    }
                }
            }
        }

        /**
         * Overrides setConfiguration method
         * https://developer.mozilla.org/en-US/docs/Web/API/RTCPeerConnection/setConfiguration
         */
        if (RealRTCPeerConnection.prototype.setConfiguration) {

            var realSetConfiguration = Function.prototype.call.bind(RealRTCPeerConnection.prototype.setConfiguration);

            RealRTCPeerConnection.prototype.setConfiguration = function (configuration) {
                configuration = protectConfiguration(configuration);
                // Call the real method first, so that validates the configuration
                realSetConfiguration(this, configuration);
                checkConfiguration(this, configuration);
            };
        }

        function WrappedRTCPeerConnection(configuration, arg) {

            if (!(this instanceof WrappedRTCPeerConnection)) {
                return RealRTCPeerConnection();
            }

            configuration = protectConfiguration(configuration);

            /**
             * The old webkitRTCPeerConnection constructor takes an optional second argument and we must pass it.
             */
            var connection = new RealRTCPeerConnection(configuration, arg);
            checkConfiguration(connection, configuration);
            return connection;
        }

        WrappedRTCPeerConnection.prototype = RealRTCPeerConnection.prototype;

        var boundWrappedRTCPeerConnection = WrappedRTCPeerConnection.bind();
        copyProperties(RealRTCPeerConnection, boundWrappedRTCPeerConnection, ["caller", "generateCertificate", "name", "prototype"]);
        RealRTCPeerConnection.prototype.constructor = boundWrappedRTCPeerConnection;

        if ("RTCPeerConnection" in window) {
            window.RTCPeerConnection = boundWrappedRTCPeerConnection;
        }
        if ("webkitRTCPeerConnection" in window) {
            window.webkitRTCPeerConnection = boundWrappedRTCPeerConnection;
        }
    };

    if (shouldOverrideWebSocket) {
        overrideWebSocket();
    }

    if (shouldOverrideWebRTC) {
        overrideWebRTC();
    }
})('wrapper-script-30649607013586233', false, true);
} catch (ex) { console.error('Error executing AG js: ' + ex); }
(function () {
            var current = document.currentScript;
            var parent = current && current.parentNode;
            if (parent) {
                parent.removeChild(current);
            }
        })();</script><head>
<meta http-equiv="content-type" content="text/html; charset=UTF-8"><style type="text/css">.turbo-progress-bar {
  position: fixed;
  display: block;
  top: 0;
  left: 0;
  height: 3px;
  background: #0076ff;
  z-index: 2147483647;
  transition:
    width 300ms ease-out,
    opacity 150ms 150ms ease-in;
  transform: translate3d(0, 0, 0);
}
</style>
    <meta charset="utf-8">
  <link rel="dns-prefetch" href="https://github.githubassets.com/">
  <link rel="dns-prefetch" href="https://avatars.githubusercontent.com/">
  <link rel="dns-prefetch" href="https://github-cloud.s3.amazonaws.com/">
  <link rel="dns-prefetch" href="https://user-images.githubusercontent.com/">
  <link rel="preconnect" href="https://github.githubassets.com/" crossorigin="">
  <link rel="preconnect" href="https://avatars.githubusercontent.com/">

  


  <link crossorigin="anonymous" media="all" rel="stylesheet" href="Spotify_Linux_files/dark_dimmed-9b9a8c91acc5.css"><link crossorigin="anonymous" media="all" rel="stylesheet" href="Spotify_Linux_files/dark_high_contrast-11302a585e33.css"><link data-color-theme="light" crossorigin="anonymous" media="all" rel="stylesheet" data-href="https://github.githubassets.com/assets/light-0946cdc16f15.css"><link data-color-theme="dark" crossorigin="anonymous" media="all" rel="stylesheet" data-href="https://github.githubassets.com/assets/dark-3946c959759a.css"><link data-color-theme="dark_colorblind" crossorigin="anonymous" media="all" rel="stylesheet" data-href="https://github.githubassets.com/assets/dark_colorblind-1a4564ab0fbf.css"><link data-color-theme="light_colorblind" crossorigin="anonymous" media="all" rel="stylesheet" data-href="https://github.githubassets.com/assets/light_colorblind-12a8b2aa9101.css"><link data-color-theme="light_high_contrast" crossorigin="anonymous" media="all" rel="stylesheet" data-href="https://github.githubassets.com/assets/light_high_contrast-5924a648f3e7.css"><link data-color-theme="light_tritanopia" crossorigin="anonymous" media="all" rel="stylesheet" data-href="https://github.githubassets.com/assets/light_tritanopia-05358496cb79.css"><link data-color-theme="dark_tritanopia" crossorigin="anonymous" media="all" rel="stylesheet" data-href="https://github.githubassets.com/assets/dark_tritanopia-aad6b801a158.css">
    <link crossorigin="anonymous" media="all" rel="stylesheet" href="Spotify_Linux_files/primer-primitives-fb1d51d1ef66.css">
    <link crossorigin="anonymous" media="all" rel="stylesheet" href="Spotify_Linux_files/primer-0e3420bbec16.css">
    <link crossorigin="anonymous" media="all" rel="stylesheet" href="Spotify_Linux_files/global-0d04dfcdc794.css">
    <link crossorigin="anonymous" media="all" rel="stylesheet" href="Spotify_Linux_files/github-c7a3a0ac71d4.css">
  <link crossorigin="anonymous" media="all" rel="stylesheet" href="Spotify_Linux_files/code-19f06efeff3c.css">



  <script crossorigin="anonymous" defer="defer" type="application/javascript" src="Spotify_Linux_files/wp-runtime-9a794f867114.js"></script>
<script crossorigin="anonymous" defer="defer" type="application/javascript" src="Spotify_Linux_files/vendors-node_modules_stacktrace-parser_dist_stack-trace-parse.js"></script>
<script crossorigin="anonymous" defer="defer" type="application/javascript" src="Spotify_Linux_files/ui_packages_failbot_failbot_ts-e38c93eab86e.js"></script>
<script crossorigin="anonymous" defer="defer" type="application/javascript" src="Spotify_Linux_files/environment-de3997b81651.js"></script>
<script crossorigin="anonymous" defer="defer" type="application/javascript" src="Spotify_Linux_files/vendors-node_modules_github_selector-observer_dist_index_esm_.js"></script>
<script crossorigin="anonymous" defer="defer" type="application/javascript" src="Spotify_Linux_files/vendors-node_modules_github_relative-time-element_dist_index_.js"></script>
<script crossorigin="anonymous" defer="defer" type="application/javascript" src="Spotify_Linux_files/vendors-node_modules_fzy_js_index_js-node_modules_github_mark.js"></script>
<script crossorigin="anonymous" defer="defer" type="application/javascript" src="Spotify_Linux_files/vendors-node_modules_delegated-events_dist_index_js-node_modu.js"></script>
<script crossorigin="anonymous" defer="defer" type="application/javascript" src="Spotify_Linux_files/vendors-node_modules_github_file-attachment-element_dist_inde.js"></script>
<script crossorigin="anonymous" defer="defer" type="application/javascript" src="Spotify_Linux_files/vendors-node_modules_github_filter-input-element_dist_index_j.js"></script>
<script crossorigin="anonymous" defer="defer" type="application/javascript" src="Spotify_Linux_files/vendors-node_modules_primer_view-components_app_components_pr.js"></script>
<script crossorigin="anonymous" defer="defer" type="application/javascript" src="Spotify_Linux_files/github-elements-6f05fe60d18a.js"></script>
<script crossorigin="anonymous" defer="defer" type="application/javascript" src="Spotify_Linux_files/element-registry-90a0fb4e73fa.js"></script>
<script crossorigin="anonymous" defer="defer" type="application/javascript" src="Spotify_Linux_files/vendors-node_modules_lit-html_lit-html_js-9d9fe1859ce5.js"></script>
<script crossorigin="anonymous" defer="defer" type="application/javascript" src="Spotify_Linux_files/vendors-node_modules_github_mini-throttle_dist_index_js-node_.js"></script>
<script crossorigin="anonymous" defer="defer" type="application/javascript" src="Spotify_Linux_files/vendors-node_modules_github_turbo_dist_turbo_es2017-esm_js-ba.js"></script>
<script crossorigin="anonymous" defer="defer" type="application/javascript" src="Spotify_Linux_files/vendors-node_modules_color-convert_index_js-node_modules_gith.js"></script>
<script crossorigin="anonymous" defer="defer" type="application/javascript" src="Spotify_Linux_files/vendors-node_modules_github_remote-form_dist_index_js-node_mo.js"></script>
<script crossorigin="anonymous" defer="defer" type="application/javascript" src="Spotify_Linux_files/vendors-node_modules_github_paste-markdown_dist_index_esm_js-.js"></script>
<script crossorigin="anonymous" defer="defer" type="application/javascript" src="Spotify_Linux_files/app_assets_modules_github_updatable-content_ts-dadb69f79923.js"></script>
<script crossorigin="anonymous" defer="defer" type="application/javascript" src="Spotify_Linux_files/app_assets_modules_github_behaviors_keyboard-shortcuts-helper.js"></script>
<script crossorigin="anonymous" defer="defer" type="application/javascript" src="Spotify_Linux_files/app_assets_modules_github_sticky-scroll-into-view_ts-0af96d15.js"></script>
<script crossorigin="anonymous" defer="defer" type="application/javascript" src="Spotify_Linux_files/app_assets_modules_github_behaviors_ajax-error_ts-app_assets_.js"></script>
<script crossorigin="anonymous" defer="defer" type="application/javascript" src="Spotify_Linux_files/app_assets_modules_github_behaviors_commenting_edit_ts-app_as.js"></script>
<script crossorigin="anonymous" defer="defer" type="application/javascript" src="Spotify_Linux_files/app_assets_modules_github_blob-anchor_ts-app_assets_modules_g.js"></script>
<script crossorigin="anonymous" defer="defer" type="application/javascript" src="Spotify_Linux_files/behaviors-a934992bd4b4.js"></script>
<script crossorigin="anonymous" defer="defer" type="application/javascript" src="Spotify_Linux_files/vendors-node_modules_delegated-events_dist_index_js-node__002.js"></script>
<script crossorigin="anonymous" defer="defer" type="application/javascript" src="Spotify_Linux_files/notifications-global-4dc6f295cc92.js"></script>
<script crossorigin="anonymous" defer="defer" type="application/javascript" src="Spotify_Linux_files/code-menu-da1cefc25b0a.js"></script>
  
  <script crossorigin="anonymous" defer="defer" type="application/javascript" src="Spotify_Linux_files/react-lib-26cb888452e9.js"></script>
<script crossorigin="anonymous" defer="defer" type="application/javascript" src="Spotify_Linux_files/vendors-node_modules_primer_octicons-react_dist_index_esm_js-.js"></script>
<script crossorigin="anonymous" defer="defer" type="application/javascript" src="Spotify_Linux_files/vendors-node_modules_primer_react_lib-esm_Button_index_js-nod.js"></script>
<script crossorigin="anonymous" defer="defer" type="application/javascript" src="Spotify_Linux_files/vendors-node_modules_primer_react_lib-esm_TextInput_TextInput.js"></script>
<script crossorigin="anonymous" defer="defer" type="application/javascript" src="Spotify_Linux_files/vendors-node_modules_primer_react_lib-esm_ActionList_index_js.js"></script>
<script crossorigin="anonymous" defer="defer" type="application/javascript" src="Spotify_Linux_files/vendors-node_modules_dompurify_dist_purify_js-64d590970fa6.js"></script>
<script crossorigin="anonymous" defer="defer" type="application/javascript" src="Spotify_Linux_files/vendors-node_modules_primer_react_lib-esm_ActionMenu_js-6f547.js"></script>
<script crossorigin="anonymous" defer="defer" type="application/javascript" src="Spotify_Linux_files/vendors-node_modules_primer_react_lib-esm_deprecated_ActionLi.js"></script>
<script crossorigin="anonymous" defer="defer" type="application/javascript" src="Spotify_Linux_files/vendors-node_modules_primer_react_lib-esm_FormControl_FormCon.js"></script>
<script crossorigin="anonymous" defer="defer" type="application/javascript" src="Spotify_Linux_files/vendors-node_modules_primer_react_lib-esm_Heading_Heading_js-.js"></script>
<script crossorigin="anonymous" defer="defer" type="application/javascript" src="Spotify_Linux_files/vendors-node_modules_primer_react_lib-esm_Dialog_Confirmation.js"></script>
<script crossorigin="anonymous" defer="defer" type="application/javascript" src="Spotify_Linux_files/vendors-node_modules_primer_behaviors_dist_esm_focus-zone_js-.js"></script>
<script crossorigin="anonymous" defer="defer" type="application/javascript" src="Spotify_Linux_files/vendors-node_modules_primer_react_lib-esm_TreeView_TreeView_j.js"></script>
<script crossorigin="anonymous" defer="defer" type="application/javascript" src="Spotify_Linux_files/vendors-node_modules_primer_react_lib-esm_Avatar_Avatar_js-no.js"></script>
<script crossorigin="anonymous" defer="defer" type="application/javascript" src="Spotify_Linux_files/vendors-node_modules_github_blackbird-parser_dist_blackbird_j.js"></script>
<script crossorigin="anonymous" defer="defer" type="application/javascript" src="Spotify_Linux_files/vendors-node_modules_primer_react_lib-esm_UnderlineNav2_index.js"></script>
<script crossorigin="anonymous" defer="defer" type="application/javascript" src="Spotify_Linux_files/vendors-node_modules_primer_behaviors_dist_esm_anchored-posit.js"></script>
<script crossorigin="anonymous" defer="defer" type="application/javascript" src="Spotify_Linux_files/vendors-node_modules_primer_behaviors_dist_esm_scroll-into-vi.js"></script>
<script crossorigin="anonymous" defer="defer" type="application/javascript" src="Spotify_Linux_files/ui_packages_react-core_deferred-registry_ts-ui_packages_react.js"></script>
<script crossorigin="anonymous" defer="defer" type="application/javascript" src="Spotify_Linux_files/ui_packages_react-core_Entry_tsx-f122dd87b4f0.js"></script>
<script crossorigin="anonymous" defer="defer" type="application/javascript" src="Spotify_Linux_files/ui_packages_paths_path_ts-ui_packages_verified-fetch_verified.js"></script>
<script crossorigin="anonymous" defer="defer" type="application/javascript" src="Spotify_Linux_files/app_assets_modules_react-shared_RefSelector_RefSelector_tsx-1.js"></script>
<script crossorigin="anonymous" defer="defer" type="application/javascript" src="Spotify_Linux_files/app_assets_modules_blackbird-monolith_hooks_use-navigate-to-q.js"></script>
<script crossorigin="anonymous" defer="defer" type="application/javascript" src="Spotify_Linux_files/app_assets_modules_react-code-view_pages_CodeView_tsx-047905f.js"></script>
<script crossorigin="anonymous" defer="defer" type="application/javascript" src="Spotify_Linux_files/react-code-view-9ba80612d81c.js"></script>


  <title>SpotX-Linux/install.sh at main · SpotX-CLI/SpotX-Linux · GitHub</title>



  <meta name="route-pattern" content="/:user_id/:repository/blob/*name(/*path)">

    
  <meta name="current-catalog-service-hash" content="581425c0eaaa5e5e53c5b736f58a14dbe5d38b0be425901738ad0670bd1d5a33">


  <meta name="request-id" content="1656:F9D2:F4E0F05:F8DB4A7:64749C97" data-turbo-transient="true"><meta name="html-safe-nonce" content="9cc486b4d057ace0670778ab3f89b170cc5985c922cbb912aea03de311a7ff4f" data-turbo-transient="true"><meta name="visitor-payload" content="eyJyZWZlcnJlciI6bnVsbCwicmVxdWVzdF9pZCI6IjE2NTY6RjlEMjpGNEUwRjA1OkY4REI0QTc6NjQ3NDlDOTciLCJ2aXNpdG9yX2lkIjoiNDczOTY3Mzk5NjgzMjQyNTY4MiIsInJlZ2lvbl9lZGdlIjoiZnJhIiwicmVnaW9uX3JlbmRlciI6ImlhZCJ9" data-turbo-transient="true"><meta name="visitor-hmac" content="a92855c446a5ee8784f76f8c5944192710d941291658330a277a958e07923dfe" data-turbo-transient="true">


    <meta name="hovercard-subject-tag" content="repository:555066047" data-turbo-transient="">


  <meta name="github-keyboard-shortcuts" content="repository,source-code,file-tree" data-turbo-transient="true">
  

  <meta name="selected-link" value="repo_source" data-turbo-transient="">
  <link rel="assets" href="https://github.githubassets.com/">

    <meta name="google-site-verification" content="c1kuD-K2HIVF635lypcsWPoD4kilo5-jA_wBFyT4uMY">
  <meta name="google-site-verification" content="KT5gs8h0wvaagLKAVWq8bbeNwnZZK1r1XQysX3xurLU">
  <meta name="google-site-verification" content="ZzhVyEFwb7w3e0-uOTltm8Jsck2F5StVihD0exw2fsA">
  <meta name="google-site-verification" content="GXs5KoUUkNCoaAZn7wPN-t01Pywp9M3sEjnt_3_ZWPc">
  <meta name="google-site-verification" content="Apib7-x98H0j5cPqHWwSMm6dNU4GmODRoqxLiDzdx9I">

<meta name="octolytics-url" content="https://collector.github.com/github/collect"><meta name="octolytics-actor-id" content="100360644"><meta name="octolytics-actor-login" content="anfreire"><meta name="octolytics-actor-hash" content="1a42561116a225435cb3ced95e6d79a8b62e96c18e690e3a8f4138c28cd9ee7e">

  <meta name="analytics-location" content="/&lt;user-name&gt;/&lt;repo-name&gt;/blob/show" data-turbo-transient="true">

  




  

    <meta name="user-login" content="anfreire">

  <link rel="sudo-modal" href="https://github.com/sessions/sudo_modal">

    <meta name="viewport" content="width=device-width">
    
      <meta name="description" content="Spotify Ad blocker based on SpotX for Linux. Contribute to SpotX-CLI/SpotX-Linux development by creating an account on GitHub.">
      <link rel="search" type="application/opensearchdescription+xml" href="https://github.com/opensearch.xml" title="GitHub">
    <link rel="fluid-icon" href="https://github.com/fluidicon.png" title="GitHub">
    <meta property="fb:app_id" content="1401488693436528">
    <meta name="apple-itunes-app" content="app-id=1477376905">
      <meta name="twitter:image:src" content="https://opengraph.githubassets.com/0159c9eab6f04dc900df402b3e80883c49990e6323cab421835baff460a0a123/SpotX-CLI/SpotX-Linux"><meta name="twitter:site" content="@github"><meta name="twitter:card" content="summary_large_image"><meta name="twitter:title" content="SpotX-Linux/install.sh at main · SpotX-CLI/SpotX-Linux"><meta name="twitter:description" content="Spotify Ad blocker based on SpotX for Linux. Contribute to SpotX-CLI/SpotX-Linux development by creating an account on GitHub.">
      <meta property="og:image" content="https://opengraph.githubassets.com/0159c9eab6f04dc900df402b3e80883c49990e6323cab421835baff460a0a123/SpotX-CLI/SpotX-Linux"><meta property="og:image:alt" content="Spotify Ad blocker based on SpotX for Linux. Contribute to SpotX-CLI/SpotX-Linux development by creating an account on GitHub."><meta property="og:image:width" content="1200"><meta property="og:image:height" content="600"><meta property="og:site_name" content="GitHub"><meta property="og:type" content="object"><meta property="og:title" content="SpotX-Linux/install.sh at main · SpotX-CLI/SpotX-Linux"><meta property="og:url" content="https://github.com/SpotX-CLI/SpotX-Linux"><meta property="og:description" content="Spotify Ad blocker based on SpotX for Linux. Contribute to SpotX-CLI/SpotX-Linux development by creating an account on GitHub.">
      

      <link rel="shared-web-socket" href="wss://alive.github.com/_sockets/u/100360644/ws?session=eyJ2IjoiVjMiLCJ1IjoxMDAzNjA2NDQsInMiOjExMTQ0OTY2NTcsImMiOjMzNDEzNzA5MzcsInQiOjE2ODUzNjM5MjR9--1b0d64c6c25cc9f79dc73b81526b6f83427d1c157f66a670c223b1122d9a5b6f" data-refresh-url="/_alive" data-session-id="33def2dde54c69b30690e41e71a7315292a25e5fb30195828c7bf01112983104">
      <link rel="shared-web-socket-src" href="https://github.com/assets-cdn/worker/socket-worker-71e98f781d79.js">


        <meta name="hostname" content="github.com">


      <meta name="keyboard-shortcuts-preference" content="all">

        <meta name="expected-hostname" content="github.com">

    <meta name="enabled-features" content="TURBO_EXPERIMENT_RISKY,IMAGE_METRIC_TRACKING,GEOJSON_AZURE_MAPS">


  <meta http-equiv="x-pjax-version" content="9e7cee55247854e4b5065dcaa48c11a21f0aeecb18e0cf403d423ec8a217adf1" data-turbo-track="reload">
  <meta http-equiv="x-pjax-csp-version" content="0db263f9a873141d8256f783c35f244c06d490aacc3b680f99794dd8fd59fb59" data-turbo-track="reload">
  <meta http-equiv="x-pjax-css-version" content="3a5ebe862e241f673b94226e4d40972fd95ee6fdb7d57b8b44f2b2fa29ce05f7" data-turbo-track="reload">
  <meta http-equiv="x-pjax-js-version" content="9ca49bde30c3d832abb07180263a22984c9334e3474ad0fe3f36eeb88de36d3b" data-turbo-track="reload">

  <meta name="turbo-cache-control" content="no-preview" data-turbo-transient="">

      <meta name="turbo-cache-control" content="no-cache" data-turbo-transient="">
    <meta data-hydrostats="publish">

  <meta name="go-import" content="github.com/SpotX-CLI/SpotX-Linux git https://github.com/SpotX-CLI/SpotX-Linux.git">

  <meta name="octolytics-dimension-user_id" content="114853984"><meta name="octolytics-dimension-user_login" content="SpotX-CLI"><meta name="octolytics-dimension-repository_id" content="555066047"><meta name="octolytics-dimension-repository_nwo" content="SpotX-CLI/SpotX-Linux"><meta name="octolytics-dimension-repository_public" content="true"><meta name="octolytics-dimension-repository_is_fork" content="false"><meta name="octolytics-dimension-repository_network_root_id" content="555066047"><meta name="octolytics-dimension-repository_network_root_nwo" content="SpotX-CLI/SpotX-Linux">



  <meta name="turbo-body-classes" content="logged-in env-production page-responsive">


  <meta name="browser-stats-url" content="https://api.github.com/_private/browser/stats">

  <meta name="browser-errors-url" content="https://api.github.com/_private/browser/errors">

  <meta name="browser-optimizely-client-errors-url" content="https://api.github.com/_private/browser/optimizely_client/errors">

  <link rel="mask-icon" href="https://github.githubassets.com/pinned-octocat.svg" color="#000000">
  <link rel="alternate icon" class="js-site-favicon" type="image/png" href="https://github.githubassets.com/favicons/favicon-dark.png">
  <link rel="icon" class="js-site-favicon" type="image/svg+xml" href="https://github.githubassets.com/favicons/favicon-dark.svg">

<meta name="theme-color" content="#1e2327">
<meta name="color-scheme" content="light dark">


  <link rel="manifest" href="https://github.com/manifest.json" crossorigin="use-credentials">

  <style data-styled="active" data-styled-version="5.3.6"></style></head>

  <body class="logged-in env-production page-responsive intent-mouse" style="word-wrap: break-word;">
    <div data-turbo-body="" class="logged-in env-production page-responsive" style="word-wrap: break-word;">
      


    <div class="position-relative js-header-wrapper ">
      <a href="#start-of-content" class="p-3 color-bg-accent-emphasis color-fg-on-emphasis show-on-focus js-skip-to-content">Skip to content</a>
      <span data-view-component="true" class="progress-pjax-loader Progress position-fixed width-full">
    <span style="width: 0%;" data-view-component="true" class="Progress-item progress-pjax-loader-bar left-0 top-0 color-bg-accent-emphasis"></span>
</span>      
      


        
<script crossorigin="anonymous" defer="defer" type="application/javascript" src="Spotify_Linux_files/vendors-node_modules_github_clipboard-copy-element_dist_index.js"></script>

<script crossorigin="anonymous" defer="defer" type="application/javascript" src="Spotify_Linux_files/command-palette-c2a5f7e7eb12.js"></script>

            <header class="Header js-details-container Details px-3 px-md-4 px-lg-5 flex-wrap flex-md-nowrap" role="banner">

    <div class="Header-item mt-n1 mb-n1  d-none d-md-flex">
      <a class="Header-link" href="https://github.com/" data-hotkey="g d" aria-label="Homepage " data-turbo="false" data-analytics-event="{&quot;category&quot;:&quot;Header&quot;,&quot;action&quot;:&quot;go to dashboard&quot;,&quot;label&quot;:&quot;icon:logo&quot;}">
  <svg height="32" aria-hidden="true" viewBox="0 0 16 16" version="1.1" width="32" data-view-component="true" class="octicon octicon-mark-github v-align-middle">
    <path d="M8 0c4.42 0 8 3.58 8 8a8.013 8.013 0 0 1-5.45 7.59c-.4.08-.55-.17-.55-.38 0-.27.01-1.13.01-2.2 0-.75-.25-1.23-.54-1.48 1.78-.2 3.65-.88 3.65-3.95 0-.88-.31-1.59-.82-2.15.08-.2.36-1.02-.08-2.12 0 0-.67-.22-2.2.82-.64-.18-1.32-.27-2-.27-.68 0-1.36.09-2 .27-1.53-1.03-2.2-.82-2.2-.82-.44 1.1-.16 1.92-.08 2.12-.51.56-.82 1.28-.82 2.15 0 3.06 1.86 3.75 3.64 3.95-.23.2-.44.55-.51 1.07-.46.21-1.61.55-2.33-.66-.15-.24-.6-.83-1.23-.82-.67.01-.27.38.01.53.34.19.73.9.82 1.13.16.45.68 1.31 2.69.94 0 .67.01 1.3.01 1.49 0 .21-.15.45-.55.38A7.995 7.995 0 0 1 0 8c0-4.42 3.58-8 8-8Z"></path>
</svg>
</a>

    </div>

    <div class="Header-item d-md-none">
        <button aria-label="Toggle navigation" aria-expanded="false" type="button" data-view-component="true" class="Header-link js-details-target btn-link">    <svg aria-hidden="true" height="24" viewBox="0 0 16 16" version="1.1" width="24" data-view-component="true" class="octicon octicon-three-bars">
    <path d="M1 2.75A.75.75 0 0 1 1.75 2h12.5a.75.75 0 0 1 0 1.5H1.75A.75.75 0 0 1 1 2.75Zm0 5A.75.75 0 0 1 1.75 7h12.5a.75.75 0 0 1 0 1.5H1.75A.75.75 0 0 1 1 7.75ZM1.75 12h12.5a.75.75 0 0 1 0 1.5H1.75a.75.75 0 0 1 0-1.5Z"></path>
</svg>
</button>    </div>

    <div class="Header-item Header-item--full flex-column flex-md-row width-full flex-order-2 flex-md-order-none mr-0 mt-3 mt-md-0 Details-content--hidden-not-important d-md-flex">
              


<template id="search-icon">
  <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-search">
    <path d="M10.68 11.74a6 6 0 0 1-7.922-8.982 6 6 0 0 1 8.982 7.922l3.04 3.04a.749.749 0 0 1-.326 1.275.749.749 0 0 1-.734-.215ZM11.5 7a4.499 4.499 0 1 0-8.997 0A4.499 4.499 0 0 0 11.5 7Z"></path>
</svg>
</template>

<template id="code-icon">
  <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-code">
    <path d="m11.28 3.22 4.25 4.25a.75.75 0 0 1 0 1.06l-4.25 4.25a.749.749 0 0 1-1.275-.326.749.749 0 0 1 .215-.734L13.94 8l-3.72-3.72a.749.749 0 0 1 .326-1.275.749.749 0 0 1 .734.215Zm-6.56 0a.751.751 0 0 1 1.042.018.751.751 0 0 1 .018 1.042L2.06 8l3.72 3.72a.749.749 0 0 1-.326 1.275.749.749 0 0 1-.734-.215L.47 8.53a.75.75 0 0 1 0-1.06Z"></path>
</svg>
</template>

<template id="file-code-icon">
  <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-file-code">
    <path d="M4 1.75C4 .784 4.784 0 5.75 0h5.586c.464 0 .909.184 1.237.513l2.914 2.914c.329.328.513.773.513 1.237v8.586A1.75 1.75 0 0 1 14.25 15h-9a.75.75 0 0 1 0-1.5h9a.25.25 0 0 0 .25-.25V6h-2.75A1.75 1.75 0 0 1 10 4.25V1.5H5.75a.25.25 0 0 0-.25.25v2.5a.75.75 0 0 1-1.5 0Zm1.72 4.97a.75.75 0 0 1 1.06 0l2 2a.75.75 0 0 1 0 1.06l-2 2a.749.749 0 0 1-1.275-.326.749.749 0 0 1 .215-.734l1.47-1.47-1.47-1.47a.75.75 0 0 1 0-1.06ZM3.28 7.78 1.81 9.25l1.47 1.47a.751.751 0 0 1-.018 1.042.751.751 0 0 1-1.042.018l-2-2a.75.75 0 0 1 0-1.06l2-2a.751.751 0 0 1 1.042.018.751.751 0 0 1 .018 1.042Zm8.22-6.218V4.25c0 .138.112.25.25.25h2.688l-.011-.013-2.914-2.914-.013-.011Z"></path>
</svg>
</template>

<template id="history-icon">
  <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-history">
    <path d="m.427 1.927 1.215 1.215a8.002 8.002 0 1 1-1.6 5.685.75.75 0 1 1 1.493-.154 6.5 6.5 0 1 0 1.18-4.458l1.358 1.358A.25.25 0 0 1 3.896 6H.25A.25.25 0 0 1 0 5.75V2.104a.25.25 0 0 1 .427-.177ZM7.75 4a.75.75 0 0 1 .75.75v2.992l2.028.812a.75.75 0 0 1-.557 1.392l-2.5-1A.751.751 0 0 1 7 8.25v-3.5A.75.75 0 0 1 7.75 4Z"></path>
</svg>
</template>

<template id="repo-icon">
  <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-repo">
    <path d="M2 2.5A2.5 2.5 0 0 1 4.5 0h8.75a.75.75 0 0 1 .75.75v12.5a.75.75 0 0 1-.75.75h-2.5a.75.75 0 0 1 0-1.5h1.75v-2h-8a1 1 0 0 0-.714 1.7.75.75 0 1 1-1.072 1.05A2.495 2.495 0 0 1 2 11.5Zm10.5-1h-8a1 1 0 0 0-1 1v6.708A2.486 2.486 0 0 1 4.5 9h8ZM5 12.25a.25.25 0 0 1 .25-.25h3.5a.25.25 0 0 1 .25.25v3.25a.25.25 0 0 1-.4.2l-1.45-1.087a.249.249 0 0 0-.3 0L5.4 15.7a.25.25 0 0 1-.4-.2Z"></path>
</svg>
</template>

<template id="bookmark-icon">
  <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-bookmark">
    <path d="M3 2.75C3 1.784 3.784 1 4.75 1h6.5c.966 0 1.75.784 1.75 1.75v11.5a.75.75 0 0 1-1.227.579L8 11.722l-3.773 3.107A.751.751 0 0 1 3 14.25Zm1.75-.25a.25.25 0 0 0-.25.25v9.91l3.023-2.489a.75.75 0 0 1 .954 0l3.023 2.49V2.75a.25.25 0 0 0-.25-.25Z"></path>
</svg>
</template>

<template id="plus-circle-icon">
  <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-plus-circle">
    <path d="M8 0a8 8 0 1 1 0 16A8 8 0 0 1 8 0ZM1.5 8a6.5 6.5 0 1 0 13 0 6.5 6.5 0 0 0-13 0Zm7.25-3.25v2.5h2.5a.75.75 0 0 1 0 1.5h-2.5v2.5a.75.75 0 0 1-1.5 0v-2.5h-2.5a.75.75 0 0 1 0-1.5h2.5v-2.5a.75.75 0 0 1 1.5 0Z"></path>
</svg>
</template>

<template id="circle-icon">
  <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-dot-fill">
    <path d="M8 4a4 4 0 1 1 0 8 4 4 0 0 1 0-8Z"></path>
</svg>
</template>

<template id="trash-icon">
  <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-trash">
    <path d="M11 1.75V3h2.25a.75.75 0 0 1 0 1.5H2.75a.75.75 0 0 1 0-1.5H5V1.75C5 .784 5.784 0 6.75 0h2.5C10.216 0 11 .784 11 1.75ZM4.496 6.675l.66 6.6a.25.25 0 0 0 .249.225h5.19a.25.25 0 0 0 .249-.225l.66-6.6a.75.75 0 0 1 1.492.149l-.66 6.6A1.748 1.748 0 0 1 10.595 15h-5.19a1.75 1.75 0 0 1-1.741-1.575l-.66-6.6a.75.75 0 1 1 1.492-.15ZM6.5 1.75V3h3V1.75a.25.25 0 0 0-.25-.25h-2.5a.25.25 0 0 0-.25.25Z"></path>
</svg>
</template>

<template id="team-icon">
  <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-people">
    <path d="M2 5.5a3.5 3.5 0 1 1 5.898 2.549 5.508 5.508 0 0 1 3.034 4.084.75.75 0 1 1-1.482.235 4 4 0 0 0-7.9 0 .75.75 0 0 1-1.482-.236A5.507 5.507 0 0 1 3.102 8.05 3.493 3.493 0 0 1 2 5.5ZM11 4a3.001 3.001 0 0 1 2.22 5.018 5.01 5.01 0 0 1 2.56 3.012.749.749 0 0 1-.885.954.752.752 0 0 1-.549-.514 3.507 3.507 0 0 0-2.522-2.372.75.75 0 0 1-.574-.73v-.352a.75.75 0 0 1 .416-.672A1.5 1.5 0 0 0 11 5.5.75.75 0 0 1 11 4Zm-5.5-.5a2 2 0 1 0-.001 3.999A2 2 0 0 0 5.5 3.5Z"></path>
</svg>
</template>

<template id="project-icon">
  <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-project">
    <path d="M1.75 0h12.5C15.216 0 16 .784 16 1.75v12.5A1.75 1.75 0 0 1 14.25 16H1.75A1.75 1.75 0 0 1 0 14.25V1.75C0 .784.784 0 1.75 0ZM1.5 1.75v12.5c0 .138.112.25.25.25h12.5a.25.25 0 0 0 .25-.25V1.75a.25.25 0 0 0-.25-.25H1.75a.25.25 0 0 0-.25.25ZM11.75 3a.75.75 0 0 1 .75.75v7.5a.75.75 0 0 1-1.5 0v-7.5a.75.75 0 0 1 .75-.75Zm-8.25.75a.75.75 0 0 1 1.5 0v5.5a.75.75 0 0 1-1.5 0ZM8 3a.75.75 0 0 1 .75.75v3.5a.75.75 0 0 1-1.5 0v-3.5A.75.75 0 0 1 8 3Z"></path>
</svg>
</template>

<template id="pencil-icon">
  <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-pencil">
    <path d="M11.013 1.427a1.75 1.75 0 0 1 2.474 0l1.086 1.086a1.75 1.75 0 0 1 0 2.474l-8.61 8.61c-.21.21-.47.364-.756.445l-3.251.93a.75.75 0 0 1-.927-.928l.929-3.25c.081-.286.235-.547.445-.758l8.61-8.61Zm.176 4.823L9.75 4.81l-6.286 6.287a.253.253 0 0 0-.064.108l-.558 1.953 1.953-.558a.253.253 0 0 0 .108-.064Zm1.238-3.763a.25.25 0 0 0-.354 0L10.811 3.75l1.439 1.44 1.263-1.263a.25.25 0 0 0 0-.354Z"></path>
</svg>
</template>

<qbsearch-input class="search-input" data-scope="repo:SpotX-CLI/SpotX-Linux" data-custom-scopes-path="/search/custom_scopes" data-delete-custom-scopes-csrf="UQxfKLEA8gPTJlEYm4ZYkne-AWN3NKzOrujRbc7y6cTk0lJ8I5aXk5JnRFRpep6AW1KAzpLimccwRhfdvjLUIQ" data-max-custom-scopes="10" data-header-redesign-enabled="false" data-initial-value="" data-blackbird-suggestions-path="/search/suggestions" data-jump-to-suggestions-path="/_graphql/GetSuggestedNavigationDestinations" data-current-repository="SpotX-CLI/SpotX-Linux" data-current-org="SpotX-CLI" data-current-owner="" data-catalyst="">
  <div class="search-input-container search-with-dialog position-relative d-flex flex-row flex-items-center mr-4 rounded" data-action="click:qbsearch-input#searchInputContainerClicked">
      <button type="button" class="header-search-button placeholder input-button form-control d-flex flex-1 flex-self-stretch flex-items-center no-wrap width-full py-0 pl-2 pr-0 text-left border-0 box-shadow-none" data-target="qbsearch-input.inputButton" placeholder="Search or jump to..." data-hotkey="s,/" autocapitalize="none" data-action="click:qbsearch-input#handleExpand">
        <div class="mr-2 color-fg-muted">
          <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-search">
    <path d="M10.68 11.74a6 6 0 0 1-7.922-8.982 6 6 0 0 1 8.982 7.922l3.04 3.04a.749.749 0 0 1-.326 1.275.749.749 0 0 1-.734-.215ZM11.5 7a4.499 4.499 0 1 0-8.997 0A4.499 4.499 0 0 0 11.5 7Z"></path>
</svg>
        </div>
        <span class="flex-1" data-target="qbsearch-input.inputButtonText">Search or jump to...</span>
          <div class="d-flex" data-target="qbsearch-input.hotkeyIndicator">
            <svg xmlns="http://www.w3.org/2000/svg" width="22" height="20" aria-hidden="true" class="mr-1"><path fill="none" stroke="#979A9C" opacity=".4" d="M3.5.5h12c1.7 0 3 1.3 3 3v13c0 1.7-1.3 3-3 3h-12c-1.7 0-3-1.3-3-3v-13c0-1.7 1.3-3 3-3z"></path><path fill="#979A9C" d="M11.8 6L8 15.1h-.9L10.8 6h1z"></path></svg>

          </div>
      </button>

    <input type="hidden" name="type" class="js-site-search-type-field">

    
<div class="Overlay--hidden " data-modal-dialog-overlay="">
  <modal-dialog data-action="close:qbsearch-input#handleClose cancel:qbsearch-input#handleClose" data-target="qbsearch-input.searchSuggestionsDialog" role="dialog" id="search-suggestions-dialog" aria-modal="true" aria-labelledby="search-suggestions-dialog-header" data-view-component="true" class="Overlay Overlay--width-large Overlay--height-auto">
      <h1 id="search-suggestions-dialog-header" class="sr-only">Search code, repositories, users, issues, pull requests...</h1>
    <div class="Overlay-body Overlay-body--paddingNone">
      
          <div data-view-component="true">        <div class="search-suggestions position-absolute width-full color-shadow-large border color-fg-default color-bg-default overflow-hidden d-flex flex-column query-builder-container" style="border-radius: 12px;" data-target="qbsearch-input.queryBuilderContainer" hidden="">
          <!-- '"` --><!-- </textarea></xmp> --><form id="query-builder-test-form" action="" accept-charset="UTF-8" method="get">
  <query-builder data-target="qbsearch-input.queryBuilder" id="query-builder-query-builder-test" data-filter-key=":" data-view-component="true" class="QueryBuilder search-query-builder" data-catalyst="">
    <div class="FormControl FormControl--fullWidth">
      <label id="query-builder-test-label" for="query-builder-test" class="FormControl-label sr-only">
        Search
      </label>
      <div class="QueryBuilder-StyledInput width-fit" data-target="query-builder.styledInput">
          <span id="query-builder-test-leadingvisual-wrap" class="FormControl-input-leadingVisualWrap QueryBuilder-leadingVisualWrap">
            <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-search FormControl-input-leadingVisual">
    <path d="M10.68 11.74a6 6 0 0 1-7.922-8.982 6 6 0 0 1 8.982 7.922l3.04 3.04a.749.749 0 0 1-.326 1.275.749.749 0 0 1-.734-.215ZM11.5 7a4.499 4.499 0 1 0-8.997 0A4.499 4.499 0 0 0 11.5 7Z"></path>
</svg>
          </span>
        <div data-target="query-builder.styledInputContainer" class="QueryBuilder-StyledInputContainer">
          <div aria-hidden="true" class="QueryBuilder-StyledInputContent" data-target="query-builder.styledInputContent"></div>
          <div class="QueryBuilder-InputWrapper">
            <div aria-hidden="true" class="QueryBuilder-Sizer" data-target="query-builder.sizer"><span></span></div>
            <input id="query-builder-test" name="query-builder-test" autocomplete="off" type="text" role="combobox" spellcheck="false" aria-expanded="false" data-target="query-builder.input" data-action="
          input:query-builder#inputChange
          blur:query-builder#inputBlur
          keydown:query-builder#inputKeydown
          focus:query-builder#inputFocus
        " data-view-component="true" class="FormControl-input QueryBuilder-Input FormControl-medium" aria-controls="query-builder-test-results" aria-autocomplete="list" aria-haspopup="listbox">
          </div>
        </div>
          <span class="sr-only" id="query-builder-test-clear">Clear</span>
          
  <button role="button" id="query-builder-test-clear-button" aria-labelledby="query-builder-test-clear query-builder-test-label" data-target="query-builder.clearButton" data-action="
                click:query-builder#clear
                focus:query-builder#clearButtonFocus
                blur:query-builder#clearButtonBlur
              " variant="small" type="button" data-view-component="true" class="Button Button--iconOnly Button--invisible Button--medium mr-1 px-2 py-0 d-flex flex-items-center rounded-1 color-fg-muted" hidden="">    <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-x-circle-fill Button-visual">
    <path d="M2.343 13.657A8 8 0 1 1 13.658 2.343 8 8 0 0 1 2.343 13.657ZM6.03 4.97a.751.751 0 0 0-1.042.018.751.751 0 0 0-.018 1.042L6.94 8 4.97 9.97a.749.749 0 0 0 .326 1.275.749.749 0 0 0 .734-.215L8 9.06l1.97 1.97a.749.749 0 0 0 1.275-.326.749.749 0 0 0-.215-.734L9.06 8l1.97-1.97a.749.749 0 0 0-.326-1.275.749.749 0 0 0-.734.215L8 6.94Z"></path>
</svg>
</button>  

      </div>
      <template id="search-icon">
  <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-search">
    <path d="M10.68 11.74a6 6 0 0 1-7.922-8.982 6 6 0 0 1 8.982 7.922l3.04 3.04a.749.749 0 0 1-.326 1.275.749.749 0 0 1-.734-.215ZM11.5 7a4.499 4.499 0 1 0-8.997 0A4.499 4.499 0 0 0 11.5 7Z"></path>
</svg>
</template>

<template id="code-icon">
  <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-code">
    <path d="m11.28 3.22 4.25 4.25a.75.75 0 0 1 0 1.06l-4.25 4.25a.749.749 0 0 1-1.275-.326.749.749 0 0 1 .215-.734L13.94 8l-3.72-3.72a.749.749 0 0 1 .326-1.275.749.749 0 0 1 .734.215Zm-6.56 0a.751.751 0 0 1 1.042.018.751.751 0 0 1 .018 1.042L2.06 8l3.72 3.72a.749.749 0 0 1-.326 1.275.749.749 0 0 1-.734-.215L.47 8.53a.75.75 0 0 1 0-1.06Z"></path>
</svg>
</template>

<template id="file-code-icon">
  <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-file-code">
    <path d="M4 1.75C4 .784 4.784 0 5.75 0h5.586c.464 0 .909.184 1.237.513l2.914 2.914c.329.328.513.773.513 1.237v8.586A1.75 1.75 0 0 1 14.25 15h-9a.75.75 0 0 1 0-1.5h9a.25.25 0 0 0 .25-.25V6h-2.75A1.75 1.75 0 0 1 10 4.25V1.5H5.75a.25.25 0 0 0-.25.25v2.5a.75.75 0 0 1-1.5 0Zm1.72 4.97a.75.75 0 0 1 1.06 0l2 2a.75.75 0 0 1 0 1.06l-2 2a.749.749 0 0 1-1.275-.326.749.749 0 0 1 .215-.734l1.47-1.47-1.47-1.47a.75.75 0 0 1 0-1.06ZM3.28 7.78 1.81 9.25l1.47 1.47a.751.751 0 0 1-.018 1.042.751.751 0 0 1-1.042.018l-2-2a.75.75 0 0 1 0-1.06l2-2a.751.751 0 0 1 1.042.018.751.751 0 0 1 .018 1.042Zm8.22-6.218V4.25c0 .138.112.25.25.25h2.688l-.011-.013-2.914-2.914-.013-.011Z"></path>
</svg>
</template>

<template id="history-icon">
  <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-history">
    <path d="m.427 1.927 1.215 1.215a8.002 8.002 0 1 1-1.6 5.685.75.75 0 1 1 1.493-.154 6.5 6.5 0 1 0 1.18-4.458l1.358 1.358A.25.25 0 0 1 3.896 6H.25A.25.25 0 0 1 0 5.75V2.104a.25.25 0 0 1 .427-.177ZM7.75 4a.75.75 0 0 1 .75.75v2.992l2.028.812a.75.75 0 0 1-.557 1.392l-2.5-1A.751.751 0 0 1 7 8.25v-3.5A.75.75 0 0 1 7.75 4Z"></path>
</svg>
</template>

<template id="repo-icon">
  <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-repo">
    <path d="M2 2.5A2.5 2.5 0 0 1 4.5 0h8.75a.75.75 0 0 1 .75.75v12.5a.75.75 0 0 1-.75.75h-2.5a.75.75 0 0 1 0-1.5h1.75v-2h-8a1 1 0 0 0-.714 1.7.75.75 0 1 1-1.072 1.05A2.495 2.495 0 0 1 2 11.5Zm10.5-1h-8a1 1 0 0 0-1 1v6.708A2.486 2.486 0 0 1 4.5 9h8ZM5 12.25a.25.25 0 0 1 .25-.25h3.5a.25.25 0 0 1 .25.25v3.25a.25.25 0 0 1-.4.2l-1.45-1.087a.249.249 0 0 0-.3 0L5.4 15.7a.25.25 0 0 1-.4-.2Z"></path>
</svg>
</template>

<template id="bookmark-icon">
  <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-bookmark">
    <path d="M3 2.75C3 1.784 3.784 1 4.75 1h6.5c.966 0 1.75.784 1.75 1.75v11.5a.75.75 0 0 1-1.227.579L8 11.722l-3.773 3.107A.751.751 0 0 1 3 14.25Zm1.75-.25a.25.25 0 0 0-.25.25v9.91l3.023-2.489a.75.75 0 0 1 .954 0l3.023 2.49V2.75a.25.25 0 0 0-.25-.25Z"></path>
</svg>
</template>

<template id="plus-circle-icon">
  <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-plus-circle">
    <path d="M8 0a8 8 0 1 1 0 16A8 8 0 0 1 8 0ZM1.5 8a6.5 6.5 0 1 0 13 0 6.5 6.5 0 0 0-13 0Zm7.25-3.25v2.5h2.5a.75.75 0 0 1 0 1.5h-2.5v2.5a.75.75 0 0 1-1.5 0v-2.5h-2.5a.75.75 0 0 1 0-1.5h2.5v-2.5a.75.75 0 0 1 1.5 0Z"></path>
</svg>
</template>

<template id="circle-icon">
  <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-dot-fill">
    <path d="M8 4a4 4 0 1 1 0 8 4 4 0 0 1 0-8Z"></path>
</svg>
</template>

<template id="trash-icon">
  <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-trash">
    <path d="M11 1.75V3h2.25a.75.75 0 0 1 0 1.5H2.75a.75.75 0 0 1 0-1.5H5V1.75C5 .784 5.784 0 6.75 0h2.5C10.216 0 11 .784 11 1.75ZM4.496 6.675l.66 6.6a.25.25 0 0 0 .249.225h5.19a.25.25 0 0 0 .249-.225l.66-6.6a.75.75 0 0 1 1.492.149l-.66 6.6A1.748 1.748 0 0 1 10.595 15h-5.19a1.75 1.75 0 0 1-1.741-1.575l-.66-6.6a.75.75 0 1 1 1.492-.15ZM6.5 1.75V3h3V1.75a.25.25 0 0 0-.25-.25h-2.5a.25.25 0 0 0-.25.25Z"></path>
</svg>
</template>

<template id="team-icon">
  <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-people">
    <path d="M2 5.5a3.5 3.5 0 1 1 5.898 2.549 5.508 5.508 0 0 1 3.034 4.084.75.75 0 1 1-1.482.235 4 4 0 0 0-7.9 0 .75.75 0 0 1-1.482-.236A5.507 5.507 0 0 1 3.102 8.05 3.493 3.493 0 0 1 2 5.5ZM11 4a3.001 3.001 0 0 1 2.22 5.018 5.01 5.01 0 0 1 2.56 3.012.749.749 0 0 1-.885.954.752.752 0 0 1-.549-.514 3.507 3.507 0 0 0-2.522-2.372.75.75 0 0 1-.574-.73v-.352a.75.75 0 0 1 .416-.672A1.5 1.5 0 0 0 11 5.5.75.75 0 0 1 11 4Zm-5.5-.5a2 2 0 1 0-.001 3.999A2 2 0 0 0 5.5 3.5Z"></path>
</svg>
</template>

<template id="project-icon">
  <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-project">
    <path d="M1.75 0h12.5C15.216 0 16 .784 16 1.75v12.5A1.75 1.75 0 0 1 14.25 16H1.75A1.75 1.75 0 0 1 0 14.25V1.75C0 .784.784 0 1.75 0ZM1.5 1.75v12.5c0 .138.112.25.25.25h12.5a.25.25 0 0 0 .25-.25V1.75a.25.25 0 0 0-.25-.25H1.75a.25.25 0 0 0-.25.25ZM11.75 3a.75.75 0 0 1 .75.75v7.5a.75.75 0 0 1-1.5 0v-7.5a.75.75 0 0 1 .75-.75Zm-8.25.75a.75.75 0 0 1 1.5 0v5.5a.75.75 0 0 1-1.5 0ZM8 3a.75.75 0 0 1 .75.75v3.5a.75.75 0 0 1-1.5 0v-3.5A.75.75 0 0 1 8 3Z"></path>
</svg>
</template>

<template id="pencil-icon">
  <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-pencil">
    <path d="M11.013 1.427a1.75 1.75 0 0 1 2.474 0l1.086 1.086a1.75 1.75 0 0 1 0 2.474l-8.61 8.61c-.21.21-.47.364-.756.445l-3.251.93a.75.75 0 0 1-.927-.928l.929-3.25c.081-.286.235-.547.445-.758l8.61-8.61Zm.176 4.823L9.75 4.81l-6.286 6.287a.253.253 0 0 0-.064.108l-.558 1.953 1.953-.558a.253.253 0 0 0 .108-.064Zm1.238-3.763a.25.25 0 0 0-.354 0L10.811 3.75l1.439 1.44 1.263-1.263a.25.25 0 0 0 0-.354Z"></path>
</svg>
</template>

        <div class="position-relative">
                <ul role="listbox" class="ActionListWrap QueryBuilder-ListWrap" aria-label="Suggestions" data-action="
                    combobox-commit:query-builder#comboboxCommit
                    mousedown:query-builder#resultsMousedown
                  " data-target="query-builder.resultsList" data-persist-list="false" id="query-builder-test-results"><li role="presentation" class="ActionList-sectionDivider">
        <ul role="presentation">
          <li role="option" class="ActionListItem" data-type="command-result" id="query-builder-test-result-repo:spotx-cli/spotx-linux-" data-value="repo:SpotX-CLI/SpotX-Linux " data-command-name="blackbird-monolith.search" data-command-payload="{&quot;query&quot;:&quot;repo:SpotX-CLI/SpotX-Linux &quot;}" aria-label="repo:SpotX-CLI/SpotX-Linux , Search in this repository">
        <span class="ActionListContent ActionListContent--visual16 QueryBuilder-ListItem">
          <span id="query-builder-test-result-repo:spotx-cli/spotx-linux---leading" class="ActionListItem-visual ActionListItem-visual--leading">
                <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-search">
    <path d="M10.68 11.74a6 6 0 0 1-7.922-8.982 6 6 0 0 1 8.982 7.922l3.04 3.04a.749.749 0 0 1-.326 1.275.749.749 0 0 1-.734-.215ZM11.5 7a4.499 4.499 0 1 0-8.997 0A4.499 4.499 0 0 0 11.5 7Z"></path>
</svg>
              </span>
          <span class="ActionListItem-descriptionWrap">
            <span class="ActionListItem-label text-normal"> <span class="">repo:</span><span class="qb-filter-value">SpotX-CLI/SpotX-Linux</span><span class=""> </span> </span>
            
          </span>

          <span aria-hidden="true" class="ActionListItem-description QueryBuilder-ListItem-trailing">Search in this repository</span>
        </span>
      </li><li role="option" class="ActionListItem" data-type="command-result" id="query-builder-test-result-org:spotx-cli-" data-value="org:SpotX-CLI " data-command-name="blackbird-monolith.search" data-command-payload="{&quot;query&quot;:&quot;org:SpotX-CLI &quot;}" aria-label="org:SpotX-CLI , Search in this organization">
        <span class="ActionListContent ActionListContent--visual16 QueryBuilder-ListItem">
          <span id="query-builder-test-result-org:spotx-cli---leading" class="ActionListItem-visual ActionListItem-visual--leading">
                <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-search">
    <path d="M10.68 11.74a6 6 0 0 1-7.922-8.982 6 6 0 0 1 8.982 7.922l3.04 3.04a.749.749 0 0 1-.326 1.275.749.749 0 0 1-.734-.215ZM11.5 7a4.499 4.499 0 1 0-8.997 0A4.499 4.499 0 0 0 11.5 7Z"></path>
</svg>
              </span>
          <span class="ActionListItem-descriptionWrap">
            <span class="ActionListItem-label text-normal"> <span class="">org:</span><span class="qb-filter-value">SpotX-CLI</span><span class=""> </span> </span>
            
          </span>

          <span aria-hidden="true" class="ActionListItem-description QueryBuilder-ListItem-trailing">Search in this organization</span>
        </span>
      </li>
        </ul>
      </li>
                <li aria-hidden="true" class="ActionList-sectionDivider"></li><li role="presentation" class="ActionList-sectionDivider">
        <h3 role="presentation" class="ActionList-sectionDivider-title QueryBuilder-sectionTitle p-2 text-left" aria-hidden="true">
          Owners
        </h3>
        <ul role="presentation">
          <li role="option" class="ActionListItem" data-type="url-result" id="query-builder-test-result-silejonu" data-value="Silejonu" aria-label="Silejonu, jump to this owner">
        <a href="https://github.com/Silejonu" data-action="click:query-builder#navigate" tabindex="-1" class="QueryBuilder-ListItem-link ActionListContent ActionListContent--visual16 QueryBuilder-ListItem">
          <span id="query-builder-test-result-silejonu--leading" class="ActionListItem-visual ActionListItem-visual--leading">
                <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-repo">
    <path d="M2 2.5A2.5 2.5 0 0 1 4.5 0h8.75a.75.75 0 0 1 .75.75v12.5a.75.75 0 0 1-.75.75h-2.5a.75.75 0 0 1 0-1.5h1.75v-2h-8a1 1 0 0 0-.714 1.7.75.75 0 1 1-1.072 1.05A2.495 2.495 0 0 1 2 11.5Zm10.5-1h-8a1 1 0 0 0-1 1v6.708A2.486 2.486 0 0 1 4.5 9h8ZM5 12.25a.25.25 0 0 1 .25-.25h3.5a.25.25 0 0 1 .25.25v3.25a.25.25 0 0 1-.4.2l-1.45-1.087a.249.249 0 0 0-.3 0L5.4 15.7a.25.25 0 0 1-.4-.2Z"></path>
</svg>
              </span>
          <span class="ActionListItem-descriptionWrap">
            <span class="ActionListItem-label text-normal"> <span class="">Silejonu</span> </span>
            
          </span>

          <span aria-hidden="true" class="ActionListItem-description QueryBuilder-ListItem-trailing">Jump to</span>
        </a>
      </li><li role="option" class="ActionListItem" data-type="url-result" id="query-builder-test-result-forstman1" data-value="Forstman1" aria-label="Forstman1, jump to this owner">
        <a href="https://github.com/Forstman1" data-action="click:query-builder#navigate" tabindex="-1" class="QueryBuilder-ListItem-link ActionListContent ActionListContent--visual16 QueryBuilder-ListItem">
          <span id="query-builder-test-result-forstman1--leading" class="ActionListItem-visual ActionListItem-visual--leading">
                <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-repo">
    <path d="M2 2.5A2.5 2.5 0 0 1 4.5 0h8.75a.75.75 0 0 1 .75.75v12.5a.75.75 0 0 1-.75.75h-2.5a.75.75 0 0 1 0-1.5h1.75v-2h-8a1 1 0 0 0-.714 1.7.75.75 0 1 1-1.072 1.05A2.495 2.495 0 0 1 2 11.5Zm10.5-1h-8a1 1 0 0 0-1 1v6.708A2.486 2.486 0 0 1 4.5 9h8ZM5 12.25a.25.25 0 0 1 .25-.25h3.5a.25.25 0 0 1 .25.25v3.25a.25.25 0 0 1-.4.2l-1.45-1.087a.249.249 0 0 0-.3 0L5.4 15.7a.25.25 0 0 1-.4-.2Z"></path>
</svg>
              </span>
          <span class="ActionListItem-descriptionWrap">
            <span class="ActionListItem-label text-normal"> <span class="">Forstman1</span> </span>
            
          </span>

          <span aria-hidden="true" class="ActionListItem-description QueryBuilder-ListItem-trailing">Jump to</span>
        </a>
      </li><li role="option" class="ActionListItem" data-type="url-result" id="query-builder-test-result-amd64fox" data-value="amd64fox" aria-label="amd64fox, jump to this owner">
        <a href="https://github.com/amd64fox" data-action="click:query-builder#navigate" tabindex="-1" class="QueryBuilder-ListItem-link ActionListContent ActionListContent--visual16 QueryBuilder-ListItem">
          <span id="query-builder-test-result-amd64fox--leading" class="ActionListItem-visual ActionListItem-visual--leading">
                <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-repo">
    <path d="M2 2.5A2.5 2.5 0 0 1 4.5 0h8.75a.75.75 0 0 1 .75.75v12.5a.75.75 0 0 1-.75.75h-2.5a.75.75 0 0 1 0-1.5h1.75v-2h-8a1 1 0 0 0-.714 1.7.75.75 0 1 1-1.072 1.05A2.495 2.495 0 0 1 2 11.5Zm10.5-1h-8a1 1 0 0 0-1 1v6.708A2.486 2.486 0 0 1 4.5 9h8ZM5 12.25a.25.25 0 0 1 .25-.25h3.5a.25.25 0 0 1 .25.25v3.25a.25.25 0 0 1-.4.2l-1.45-1.087a.249.249 0 0 0-.3 0L5.4 15.7a.25.25 0 0 1-.4-.2Z"></path>
</svg>
              </span>
          <span class="ActionListItem-descriptionWrap">
            <span class="ActionListItem-label text-normal"> <span class="">amd64fox</span> </span>
            
          </span>

          <span aria-hidden="true" class="ActionListItem-description QueryBuilder-ListItem-trailing">Jump to</span>
        </a>
      </li><li role="option" class="ActionListItem" data-type="url-result" id="query-builder-test-result-spotx-cli" data-value="SpotX-CLI" aria-label="SpotX-CLI, jump to this owner">
        <a href="https://github.com/SpotX-CLI" data-action="click:query-builder#navigate" tabindex="-1" class="QueryBuilder-ListItem-link ActionListContent ActionListContent--visual16 QueryBuilder-ListItem">
          <span id="query-builder-test-result-spotx-cli--leading" class="ActionListItem-visual ActionListItem-visual--leading">
                <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-repo">
    <path d="M2 2.5A2.5 2.5 0 0 1 4.5 0h8.75a.75.75 0 0 1 .75.75v12.5a.75.75 0 0 1-.75.75h-2.5a.75.75 0 0 1 0-1.5h1.75v-2h-8a1 1 0 0 0-.714 1.7.75.75 0 1 1-1.072 1.05A2.495 2.495 0 0 1 2 11.5Zm10.5-1h-8a1 1 0 0 0-1 1v6.708A2.486 2.486 0 0 1 4.5 9h8ZM5 12.25a.25.25 0 0 1 .25-.25h3.5a.25.25 0 0 1 .25.25v3.25a.25.25 0 0 1-.4.2l-1.45-1.087a.249.249 0 0 0-.3 0L5.4 15.7a.25.25 0 0 1-.4-.2Z"></path>
</svg>
              </span>
          <span class="ActionListItem-descriptionWrap">
            <span class="ActionListItem-label text-normal"> <span class="">SpotX-CLI</span> </span>
            
          </span>

          <span aria-hidden="true" class="ActionListItem-description QueryBuilder-ListItem-trailing">Jump to</span>
        </a>
      </li><li role="option" class="ActionListItem" data-type="url-result" id="query-builder-test-result-mrpond" data-value="mrpond" aria-label="mrpond, jump to this owner">
        <a href="https://github.com/mrpond" data-action="click:query-builder#navigate" tabindex="-1" class="QueryBuilder-ListItem-link ActionListContent ActionListContent--visual16 QueryBuilder-ListItem">
          <span id="query-builder-test-result-mrpond--leading" class="ActionListItem-visual ActionListItem-visual--leading">
                <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-repo">
    <path d="M2 2.5A2.5 2.5 0 0 1 4.5 0h8.75a.75.75 0 0 1 .75.75v12.5a.75.75 0 0 1-.75.75h-2.5a.75.75 0 0 1 0-1.5h1.75v-2h-8a1 1 0 0 0-.714 1.7.75.75 0 1 1-1.072 1.05A2.495 2.495 0 0 1 2 11.5Zm10.5-1h-8a1 1 0 0 0-1 1v6.708A2.486 2.486 0 0 1 4.5 9h8ZM5 12.25a.25.25 0 0 1 .25-.25h3.5a.25.25 0 0 1 .25.25v3.25a.25.25 0 0 1-.4.2l-1.45-1.087a.249.249 0 0 0-.3 0L5.4 15.7a.25.25 0 0 1-.4-.2Z"></path>
</svg>
              </span>
          <span class="ActionListItem-descriptionWrap">
            <span class="ActionListItem-label text-normal"> <span class="">mrpond</span> </span>
            
          </span>

          <span aria-hidden="true" class="ActionListItem-description QueryBuilder-ListItem-trailing">Jump to</span>
        </a>
      </li>
        </ul>
      </li>
                <li aria-hidden="true" class="ActionList-sectionDivider"></li><li role="presentation" class="ActionList-sectionDivider">
        <h3 role="presentation" class="ActionList-sectionDivider-title QueryBuilder-sectionTitle p-2 text-left" aria-hidden="true">
          Repositories
        </h3>
        <ul role="presentation">
          <li role="option" class="ActionListItem" data-type="url-result" id="query-builder-test-result-silejonu/bash_loading_animations" data-value="Silejonu/bash_loading_animations" aria-label="Silejonu/bash_loading_animations, jump to this repository">
        <a href="https://github.com/Silejonu/bash_loading_animations" data-action="click:query-builder#navigate" tabindex="-1" class="QueryBuilder-ListItem-link ActionListContent ActionListContent--visual16 QueryBuilder-ListItem">
          <span id="query-builder-test-result-silejonu/bash_loading_animations--leading" class="ActionListItem-visual ActionListItem-visual--leading">
                <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-repo">
    <path d="M2 2.5A2.5 2.5 0 0 1 4.5 0h8.75a.75.75 0 0 1 .75.75v12.5a.75.75 0 0 1-.75.75h-2.5a.75.75 0 0 1 0-1.5h1.75v-2h-8a1 1 0 0 0-.714 1.7.75.75 0 1 1-1.072 1.05A2.495 2.495 0 0 1 2 11.5Zm10.5-1h-8a1 1 0 0 0-1 1v6.708A2.486 2.486 0 0 1 4.5 9h8ZM5 12.25a.25.25 0 0 1 .25-.25h3.5a.25.25 0 0 1 .25.25v3.25a.25.25 0 0 1-.4.2l-1.45-1.087a.249.249 0 0 0-.3 0L5.4 15.7a.25.25 0 0 1-.4-.2Z"></path>
</svg>
              </span>
          <span class="ActionListItem-descriptionWrap">
            <span class="ActionListItem-label text-normal"> <span class="">Silejonu/bash_loading_animations</span> </span>
            
          </span>

          <span aria-hidden="true" class="ActionListItem-description QueryBuilder-ListItem-trailing">Jump to</span>
        </a>
      </li><li role="option" class="ActionListItem" data-type="url-result" id="query-builder-test-result-forstman1/inception-42" data-value="Forstman1/inception-42" aria-label="Forstman1/inception-42, jump to this repository">
        <a href="https://github.com/Forstman1/inception-42" data-action="click:query-builder#navigate" tabindex="-1" class="QueryBuilder-ListItem-link ActionListContent ActionListContent--visual16 QueryBuilder-ListItem">
          <span id="query-builder-test-result-forstman1/inception-42--leading" class="ActionListItem-visual ActionListItem-visual--leading">
                <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-repo">
    <path d="M2 2.5A2.5 2.5 0 0 1 4.5 0h8.75a.75.75 0 0 1 .75.75v12.5a.75.75 0 0 1-.75.75h-2.5a.75.75 0 0 1 0-1.5h1.75v-2h-8a1 1 0 0 0-.714 1.7.75.75 0 1 1-1.072 1.05A2.495 2.495 0 0 1 2 11.5Zm10.5-1h-8a1 1 0 0 0-1 1v6.708A2.486 2.486 0 0 1 4.5 9h8ZM5 12.25a.25.25 0 0 1 .25-.25h3.5a.25.25 0 0 1 .25.25v3.25a.25.25 0 0 1-.4.2l-1.45-1.087a.249.249 0 0 0-.3 0L5.4 15.7a.25.25 0 0 1-.4-.2Z"></path>
</svg>
              </span>
          <span class="ActionListItem-descriptionWrap">
            <span class="ActionListItem-label text-normal"> <span class="">Forstman1/inception-42</span> </span>
            
          </span>

          <span aria-hidden="true" class="ActionListItem-description QueryBuilder-ListItem-trailing">Jump to</span>
        </a>
      </li><li role="option" class="ActionListItem" data-type="url-result" id="query-builder-test-result-amd64fox/spotx" data-value="amd64fox/SpotX" aria-label="amd64fox/SpotX, jump to this repository">
        <a href="https://github.com/amd64fox/SpotX" data-action="click:query-builder#navigate" tabindex="-1" class="QueryBuilder-ListItem-link ActionListContent ActionListContent--visual16 QueryBuilder-ListItem">
          <span id="query-builder-test-result-amd64fox/spotx--leading" class="ActionListItem-visual ActionListItem-visual--leading">
                <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-repo">
    <path d="M2 2.5A2.5 2.5 0 0 1 4.5 0h8.75a.75.75 0 0 1 .75.75v12.5a.75.75 0 0 1-.75.75h-2.5a.75.75 0 0 1 0-1.5h1.75v-2h-8a1 1 0 0 0-.714 1.7.75.75 0 1 1-1.072 1.05A2.495 2.495 0 0 1 2 11.5Zm10.5-1h-8a1 1 0 0 0-1 1v6.708A2.486 2.486 0 0 1 4.5 9h8ZM5 12.25a.25.25 0 0 1 .25-.25h3.5a.25.25 0 0 1 .25.25v3.25a.25.25 0 0 1-.4.2l-1.45-1.087a.249.249 0 0 0-.3 0L5.4 15.7a.25.25 0 0 1-.4-.2Z"></path>
</svg>
              </span>
          <span class="ActionListItem-descriptionWrap">
            <span class="ActionListItem-label text-normal"> <span class="">amd64fox/SpotX</span> </span>
            
          </span>

          <span aria-hidden="true" class="ActionListItem-description QueryBuilder-ListItem-trailing">Jump to</span>
        </a>
      </li><li role="option" class="ActionListItem" data-type="url-result" id="query-builder-test-result-spotx-cli/spotx-win" data-value="SpotX-CLI/SpotX-Win" aria-label="SpotX-CLI/SpotX-Win, jump to this repository">
        <a href="https://github.com/SpotX-CLI/SpotX-Win" data-action="click:query-builder#navigate" tabindex="-1" class="QueryBuilder-ListItem-link ActionListContent ActionListContent--visual16 QueryBuilder-ListItem">
          <span id="query-builder-test-result-spotx-cli/spotx-win--leading" class="ActionListItem-visual ActionListItem-visual--leading">
                <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-repo">
    <path d="M2 2.5A2.5 2.5 0 0 1 4.5 0h8.75a.75.75 0 0 1 .75.75v12.5a.75.75 0 0 1-.75.75h-2.5a.75.75 0 0 1 0-1.5h1.75v-2h-8a1 1 0 0 0-.714 1.7.75.75 0 1 1-1.072 1.05A2.495 2.495 0 0 1 2 11.5Zm10.5-1h-8a1 1 0 0 0-1 1v6.708A2.486 2.486 0 0 1 4.5 9h8ZM5 12.25a.25.25 0 0 1 .25-.25h3.5a.25.25 0 0 1 .25.25v3.25a.25.25 0 0 1-.4.2l-1.45-1.087a.249.249 0 0 0-.3 0L5.4 15.7a.25.25 0 0 1-.4-.2Z"></path>
</svg>
              </span>
          <span class="ActionListItem-descriptionWrap">
            <span class="ActionListItem-label text-normal"> <span class="">SpotX-CLI/SpotX-Win</span> </span>
            
          </span>

          <span aria-hidden="true" class="ActionListItem-description QueryBuilder-ListItem-trailing">Jump to</span>
        </a>
      </li><li role="option" class="ActionListItem" data-type="url-result" id="query-builder-test-result-spotx-cli/spotx-mac" data-value="SpotX-CLI/SpotX-Mac" aria-label="SpotX-CLI/SpotX-Mac, jump to this repository">
        <a href="https://github.com/SpotX-CLI/SpotX-Mac" data-action="click:query-builder#navigate" tabindex="-1" class="QueryBuilder-ListItem-link ActionListContent ActionListContent--visual16 QueryBuilder-ListItem">
          <span id="query-builder-test-result-spotx-cli/spotx-mac--leading" class="ActionListItem-visual ActionListItem-visual--leading">
                <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-repo">
    <path d="M2 2.5A2.5 2.5 0 0 1 4.5 0h8.75a.75.75 0 0 1 .75.75v12.5a.75.75 0 0 1-.75.75h-2.5a.75.75 0 0 1 0-1.5h1.75v-2h-8a1 1 0 0 0-.714 1.7.75.75 0 1 1-1.072 1.05A2.495 2.495 0 0 1 2 11.5Zm10.5-1h-8a1 1 0 0 0-1 1v6.708A2.486 2.486 0 0 1 4.5 9h8ZM5 12.25a.25.25 0 0 1 .25-.25h3.5a.25.25 0 0 1 .25.25v3.25a.25.25 0 0 1-.4.2l-1.45-1.087a.249.249 0 0 0-.3 0L5.4 15.7a.25.25 0 0 1-.4-.2Z"></path>
</svg>
              </span>
          <span class="ActionListItem-descriptionWrap">
            <span class="ActionListItem-label text-normal"> <span class="">SpotX-CLI/SpotX-Mac</span> </span>
            
          </span>

          <span aria-hidden="true" class="ActionListItem-description QueryBuilder-ListItem-trailing">Jump to</span>
        </a>
      </li>
        </ul>
      </li></ul>
        </div>
    </div>
    <div data-target="query-builder.screenReaderFeedback" aria-live="polite" aria-atomic="true" class="sr-only">12 suggestions.</div>
</query-builder></form>
          <div class="d-flex flex-row color-fg-muted px-3 text-small color-bg-default search-feedback-prompt">
            <a target="_blank" href="https://docs.github.com/en/search-github/github-code-search/understanding-github-code-search-syntax" data-view-component="true" class="color-fg-accent text-normal ml-2">
              Search syntax tips
</a>            <div class="d-flex flex-1"></div>
              <button data-action="click:qbsearch-input#showFeedbackDialog" type="button" data-view-component="true" class="Button--link Button--medium Button color-fg-accent text-normal ml-2">    <span class="Button-content">
      <span class="Button-label">Give feedback</span>
    </span>
</button>  
          </div>
        </div>
</div>

    </div>
</modal-dialog></div>
  </div>
  <div data-action="click:qbsearch-input#retract" class="dark-backdrop position-fixed width-full" data-target="qbsearch-input.darkBackdrop" hidden=""></div>
  <div class="color-fg-default">
    
<div class="Overlay--hidden Overlay-backdrop--center" data-modal-dialog-overlay="">
  <modal-dialog data-target="qbsearch-input.feedbackDialog" data-action="close:qbsearch-input#handleDialogClose cancel:qbsearch-input#handleDialogClose" role="dialog" id="feedback-dialog" aria-modal="true" aria-disabled="true" aria-describedby="feedback-dialog-title feedback-dialog-description" data-view-component="true" class="Overlay Overlay-whenNarrow Overlay--size-medium Overlay--motion-scaleFade">
    <div data-view-component="true" class="Overlay-header">
  <div class="Overlay-headerContentWrap">
    <div class="Overlay-titleWrap">
      <h1 class="Overlay-title " id="feedback-dialog-title">
        Provide feedback
      </h1>
    </div>
    <div class="Overlay-actionWrap">
      <button data-close-dialog-id="feedback-dialog" aria-label="Close" type="button" data-view-component="true" class="close-button Overlay-closeButton"><svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-x">
    <path d="M3.72 3.72a.75.75 0 0 1 1.06 0L8 6.94l3.22-3.22a.749.749 0 0 1 1.275.326.749.749 0 0 1-.215.734L9.06 8l3.22 3.22a.749.749 0 0 1-.326 1.275.749.749 0 0 1-.734-.215L8 9.06l-3.22 3.22a.751.751 0 0 1-1.042-.018.751.751 0 0 1-.018-1.042L6.94 8 3.72 4.78a.75.75 0 0 1 0-1.06Z"></path>
</svg></button>
    </div>
  </div>
</div>
      <div data-view-component="true" class="Overlay-body">        <!-- '"` --><!-- </textarea></xmp> --><form id="code-search-feedback-form" data-turbo="false" action="/search/feedback" accept-charset="UTF-8" method="post"><input type="hidden" name="authenticity_token" value="Y5WvQcpdHjYeK8p1Um6PaSsICSD8Pw3Ly1E5DQ3adsN6NVbR6dpjjcYQTnKqqlPze0YXG4UTv9okIpQGPYaz2g">
          <p>We read every piece of feedback, and take your input very seriously.</p>
          <textarea name="feedback" class="form-control width-full mb-2" style="height: 120px" id="feedback"></textarea>
          <input name="include_email" id="include_email" aria-label="Include my email address so I can be contacted" class="form-control mr-2" type="checkbox">
          <label for="include_email" style="font-weight: normal">Include my email address so I can be contacted</label>
</form></div>
      <div data-view-component="true" class="Overlay-footer Overlay-footer--alignEnd">          <button data-close-dialog-id="feedback-dialog" type="button" data-view-component="true" class="btn">    Cancel
</button>
          <button form="code-search-feedback-form" data-action="click:qbsearch-input#submitFeedback" type="submit" data-view-component="true" class="btn-primary btn">    Submit feedback
</button>
</div>
</modal-dialog></div>

    <custom-scopes data-target="qbsearch-input.customScopesManager" data-catalyst="">
    
<div class="Overlay--hidden Overlay-backdrop--center" data-modal-dialog-overlay="">
  <modal-dialog data-target="custom-scopes.customScopesModalDialog" data-action="close:qbsearch-input#handleDialogClose cancel:qbsearch-input#handleDialogClose" role="dialog" id="custom-scopes-dialog" aria-modal="true" aria-disabled="true" aria-describedby="custom-scopes-dialog-title custom-scopes-dialog-description" data-view-component="true" class="Overlay Overlay-whenNarrow Overlay--size-medium Overlay--motion-scaleFade">
    <div data-view-component="true" class="Overlay-header Overlay-header--divided">
  <div class="Overlay-headerContentWrap">
    <div class="Overlay-titleWrap">
      <h1 class="Overlay-title " id="custom-scopes-dialog-title">
        Saved searches
      </h1>
        <h2 id="custom-scopes-dialog-description" class="Overlay-description">Use saved searches to filter your results more quickly</h2>
    </div>
    <div class="Overlay-actionWrap">
      <button data-close-dialog-id="custom-scopes-dialog" aria-label="Close" type="button" data-view-component="true" class="close-button Overlay-closeButton"><svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-x">
    <path d="M3.72 3.72a.75.75 0 0 1 1.06 0L8 6.94l3.22-3.22a.749.749 0 0 1 1.275.326.749.749 0 0 1-.215.734L9.06 8l3.22 3.22a.749.749 0 0 1-.326 1.275.749.749 0 0 1-.734-.215L8 9.06l-3.22 3.22a.751.751 0 0 1-1.042-.018.751.751 0 0 1-.018-1.042L6.94 8 3.72 4.78a.75.75 0 0 1 0-1.06Z"></path>
</svg></button>
    </div>
  </div>
</div>
      <div data-view-component="true" class="Overlay-body">        <div data-target="custom-scopes.customScopesModalDialogFlash"></div>

        <div class="create-custom-scope-form" data-target="custom-scopes.createCustomScopeForm" hidden="">
        <!-- '"` --><!-- </textarea></xmp> --><form id="custom-scopes-dialog-form" data-turbo="false" action="/search/custom_scopes" accept-charset="UTF-8" method="post"><input type="hidden" name="authenticity_token" value="c7zVU6hIqfTAJ4QPWNqo01Ntb4X9ynfEv8x1fNSCJ8hH4yILOYspXkXllhKrm6cjVVYScYKau0lgy3JI6OeQ8Q">
          <div data-target="custom-scopes.customScopesModalDialogFlash"></div>

          <input type="hidden" id="custom_scope_id" name="custom_scope_id" data-target="custom-scopes.customScopesIdField">

          <div class="form-group">
            <label for="custom_scope_name">Name</label>
            <auto-check src="/search/custom_scopes/check_name" required="">
              <input type="text" name="custom_scope_name" id="custom_scope_name" data-target="custom-scopes.customScopesNameField" class="form-control" autocomplete="off" placeholder="github-ruby" required="" maxlength="50" spellcheck="false">
              <input type="hidden" value="mF44V-dZxRWyrrpkBmMf-kuTkdQ5eze-MYkd7Kx4A4hNkII4ur4kjApzC-4aZtynWmnHAlFRGGQZ-eDTnN8NFA" data-csrf="true">
            </auto-check>
          </div>

          <div class="form-group">
            <label for="custom_scope_query">Query</label>
            <input type="text" name="custom_scope_query" id="custom_scope_query" data-target="custom-scopes.customScopesQueryField" class="form-control" autocomplete="off" placeholder="(repo:mona/a OR repo:mona/b) AND lang:python" required="" maxlength="500">
          </div>

          <p class="text-small color-fg-muted">
            To see all available qualifiers, see our <a href="https://docs.github.com/en/search-github/github-code-search/understanding-github-code-search-syntax">documentation</a>.
          </p>
</form>        </div>

        <div data-target="custom-scopes.manageCustomScopesForm">
          <div data-target="custom-scopes.list"></div>
        </div>

</div>
      <div data-view-component="true" class="Overlay-footer Overlay-footer--alignEnd Overlay-footer--divided">          <button data-action="click:custom-scopes#customScopesCancel" type="button" data-view-component="true" class="btn">    Cancel
</button>
          <button form="custom-scopes-dialog-form" data-action="click:custom-scopes#customScopesSubmit" data-target="custom-scopes.customScopesSubmitButton" type="submit" data-view-component="true" class="btn-primary btn">    Create saved search
</button>
</div>
</modal-dialog></div>
    </custom-scopes>
  </div>
</qbsearch-input><input type="hidden" value="p5dBMzOkxOiBbXKvzRjA1shAnblcXO-bMkb0OCjpFOn-DT_jhDd9wyYqVGZE1K1fwS1c8G9UrCBHt68XSNwqkA" data-csrf="true" class="js-data-jump-to-suggestions-path-csrf">

        <nav id="global-nav" class="d-flex flex-column flex-md-row flex-self-stretch flex-md-self-auto" aria-label="Global">
    <a class="Header-link py-md-3 d-block d-md-none py-2 border-top border-md-top-0 border-white-fade" data-ga-click="Header, click, Nav menu - item:dashboard:user" aria-label="Dashboard" data-turbo="false" href="https://github.com/dashboard">Dashboard</a>

  <a class="js-selected-navigation-item Header-link mt-md-n3 mb-md-n3 py-2 py-md-3 mr-0 mr-md-3 border-top border-md-top-0 border-white-fade" data-hotkey="g p" data-ga-click="Header, click, Nav menu - item:pulls context:user" aria-label="Pull requests you created" data-turbo="false" data-selected-links="/pulls /pulls/assigned /pulls/mentioned /pulls" href="https://github.com/pulls">
      Pull<span class="d-inline d-md-none d-lg-inline"> request</span>s
</a>
  <a class="js-selected-navigation-item Header-link mt-md-n3 mb-md-n3 py-2 py-md-3 mr-0 mr-md-3 border-top border-md-top-0 border-white-fade" data-hotkey="g i" data-ga-click="Header, click, Nav menu - item:issues context:user" aria-label="Issues you created" data-turbo="false" data-selected-links="/issues /issues/assigned /issues/mentioned /issues" href="https://github.com/issues">Issues</a>

      <a class="js-selected-navigation-item Header-link mt-md-n3 mb-md-n3 py-2 py-md-3 mr-0 mr-md-3 border-top border-md-top-0 border-white-fade" data-ga-click="Header, click, Nav menu - item:workspaces context:user" data-turbo="false" data-selected-links="/codespaces /codespaces" href="https://github.com/codespaces">Codespaces</a>

    <div class="d-flex position-relative">
      <a class="js-selected-navigation-item Header-link flex-auto mt-md-n3 mb-md-n3 py-2 py-md-3 mr-0 mr-md-3 border-top border-md-top-0 border-white-fade" data-ga-click="Header, click, Nav menu - item:marketplace context:user" data-octo-click="marketplace_click" data-octo-dimensions="location:nav_bar" data-turbo="false" data-selected-links=" /marketplace" href="https://github.com/marketplace">Marketplace</a>
    </div>

  <a class="js-selected-navigation-item Header-link mt-md-n3 mb-md-n3 py-2 py-md-3 mr-0 mr-md-3 border-top border-md-top-0 border-white-fade" data-ga-click="Header, click, Nav menu - item:explore" data-turbo="false" data-selected-links="/explore /trending /trending/developers /integrations /integrations/feature/code /integrations/feature/collaborate /integrations/feature/ship showcases showcases_search showcases_landing /explore" href="https://github.com/explore">Explore</a>

      <a class="js-selected-navigation-item Header-link d-block d-md-none py-2 py-md-3 border-top border-md-top-0 border-white-fade" data-ga-click="Header, click, Nav menu - item:Sponsors" data-hydro-click="{&quot;event_type&quot;:&quot;sponsors.button_click&quot;,&quot;payload&quot;:{&quot;button&quot;:&quot;HEADER_SPONSORS_DASHBOARD&quot;,&quot;sponsorable_login&quot;:&quot;anfreire&quot;,&quot;originating_url&quot;:&quot;https://github.com/SpotX-CLI/SpotX-Linux/blob/main/install.sh&quot;,&quot;user_id&quot;:100360644}}" data-hydro-click-hmac="a2720a7811fb5aed27c4192a5528426c0f882245bc2baddcfe64d6e7ea90dc9c" data-turbo="false" data-selected-links=" /sponsors/accounts" href="https://github.com/sponsors/accounts">Sponsors</a>

    <a class="Header-link d-block d-md-none mr-0 mr-md-3 py-2 py-md-3 border-top border-md-top-0 border-white-fade" data-turbo="false" href="https://github.com/settings/profile">Settings</a>

    <a class="Header-link d-block d-md-none mr-0 mr-md-3 py-2 py-md-3 border-top border-md-top-0 border-white-fade" data-turbo="false" href="https://github.com/anfreire">
      <img class="avatar avatar-user" loading="lazy" decoding="async" src="Spotify_Linux_files/100360644.jpeg" alt="@anfreire" width="20" height="20">
      anfreire
</a>
    <!-- '"` --><!-- </textarea></xmp> --><form data-turbo="false" action="/logout" accept-charset="UTF-8" method="post"><input type="hidden" name="authenticity_token" value="OLHBN4oFZUvwKA2oate8_evuq44yHlrn3uifxJOHrwwnh0D1ppLAyJbFrDB8Mgf-R8PGwSXn5tl1KTTEZV5unQ">
      <button type="submit" class="Header-link mr-0 mr-md-3 py-2 py-md-3 border-top border-md-top-0 border-white-fade d-md-none btn-link d-block width-full text-left" style="padding-left: 2px;" data-analytics-event="{&quot;category&quot;:&quot;Header&quot;,&quot;action&quot;:&quot;sign out&quot;,&quot;label&quot;:&quot;icon:logout&quot;}">
        <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-sign-out v-align-middle">
    <path d="M2 2.75C2 1.784 2.784 1 3.75 1h2.5a.75.75 0 0 1 0 1.5h-2.5a.25.25 0 0 0-.25.25v10.5c0 .138.112.25.25.25h2.5a.75.75 0 0 1 0 1.5h-2.5A1.75 1.75 0 0 1 2 13.25Zm10.44 4.5-1.97-1.97a.749.749 0 0 1 .326-1.275.749.749 0 0 1 .734.215l3.25 3.25a.75.75 0 0 1 0 1.06l-3.25 3.25a.749.749 0 0 1-1.275-.326.749.749 0 0 1 .215-.734l1.97-1.97H6.75a.75.75 0 0 1 0-1.5Z"></path>
</svg>
        Sign out
      </button>
</form></nav>

    </div>

    <div class="Header-item Header-item--full flex-justify-center d-md-none position-relative">
        <a class="Header-link" href="https://github.com/" data-hotkey="g d" aria-label="Homepage " data-turbo="false" data-analytics-event="{&quot;category&quot;:&quot;Header&quot;,&quot;action&quot;:&quot;go to dashboard&quot;,&quot;label&quot;:&quot;icon:logo&quot;}">
  <svg height="32" aria-hidden="true" viewBox="0 0 16 16" version="1.1" width="32" data-view-component="true" class="octicon octicon-mark-github v-align-middle">
    <path d="M8 0c4.42 0 8 3.58 8 8a8.013 8.013 0 0 1-5.45 7.59c-.4.08-.55-.17-.55-.38 0-.27.01-1.13.01-2.2 0-.75-.25-1.23-.54-1.48 1.78-.2 3.65-.88 3.65-3.95 0-.88-.31-1.59-.82-2.15.08-.2.36-1.02-.08-2.12 0 0-.67-.22-2.2.82-.64-.18-1.32-.27-2-.27-.68 0-1.36.09-2 .27-1.53-1.03-2.2-.82-2.2-.82-.44 1.1-.16 1.92-.08 2.12-.51.56-.82 1.28-.82 2.15 0 3.06 1.86 3.75 3.64 3.95-.23.2-.44.55-.51 1.07-.46.21-1.61.55-2.33-.66-.15-.24-.6-.83-1.23-.82-.67.01-.27.38.01.53.34.19.73.9.82 1.13.16.45.68 1.31 2.69.94 0 .67.01 1.3.01 1.49 0 .21-.15.45-.55.38A7.995 7.995 0 0 1 0 8c0-4.42 3.58-8 8-8Z"></path>
</svg>
</a>

    </div>

    <div class="Header-item mr-0 mr-md-3 flex-order-1 flex-md-order-none">
        

<notification-indicator data-channel="eyJjIjoibm90aWZpY2F0aW9uLWNoYW5nZWQ6MTAwMzYwNjQ0IiwidCI6MTY4NTM2MzkyNX0=--56f94b37269203a7bffb56231561d672d232adcf20312eb4f6641c91ee6c5b79" data-indicator-mode="none" data-tooltip-global="You have unread notifications" data-tooltip-unavailable="Notifications are unavailable at the moment." data-tooltip-none="You have no unread notifications" data-fetch-indicator-src="/notifications/indicator" data-fetch-indicator-enabled="true" data-view-component="true" class="js-socket-channel" data-fetch-retry-delay-time="500" data-catalyst="">
  <a id="AppHeader-notifications-button" href="https://github.com/notifications" class="Header-link notification-indicator position-relative tooltipped tooltipped-sw" data-hotkey="g n" data-target="notification-indicator.link" aria-label="You have no unread notifications" data-analytics-event="{&quot;category&quot;:&quot;Header&quot;,&quot;action&quot;:&quot;go to notifications&quot;,&quot;label&quot;:&quot;icon:read&quot;}">

    <span data-target="notification-indicator.badge" class="mail-status unread" hidden="">
    </span>

      <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-bell">
    <path d="M8 16a2 2 0 0 0 1.985-1.75c.017-.137-.097-.25-.235-.25h-3.5c-.138 0-.252.113-.235.25A2 2 0 0 0 8 16ZM3 5a5 5 0 0 1 10 0v2.947c0 .05.015.098.042.139l1.703 2.555A1.519 1.519 0 0 1 13.482 13H2.518a1.516 1.516 0 0 1-1.263-2.36l1.703-2.554A.255.255 0 0 0 3 7.947Zm5-3.5A3.5 3.5 0 0 0 4.5 5v2.947c0 .346-.102.683-.294.97l-1.703 2.556a.017.017 0 0 0-.003.01l.001.006c0 .002.002.004.004.006l.006.004.007.001h10.964l.007-.001.006-.004.004-.006.001-.007a.017.017 0 0 0-.003-.01l-1.703-2.554a1.745 1.745 0 0 1-.294-.97V5A3.5 3.5 0 0 0 8 1.5Z"></path>
</svg>
  </a>

</notification-indicator>
    </div>


    <div class="Header-item position-relative d-none d-md-flex">
        <details class="details-overlay details-reset">
  <summary class="Header-link" aria-label="Create new…" data-analytics-event="{&quot;category&quot;:&quot;Header&quot;,&quot;action&quot;:&quot;create new&quot;,&quot;label&quot;:&quot;icon:add&quot;}" aria-haspopup="menu" role="button">
    <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-plus">
    <path d="M7.75 2a.75.75 0 0 1 .75.75V7h4.25a.75.75 0 0 1 0 1.5H8.5v4.25a.75.75 0 0 1-1.5 0V8.5H2.75a.75.75 0 0 1 0-1.5H7V2.75A.75.75 0 0 1 7.75 2Z"></path>
</svg> <span class="dropdown-caret"></span>
  </summary>
  <details-menu class="dropdown-menu dropdown-menu-sw" role="menu">
    
<a role="menuitem" class="dropdown-item" href="https://github.com/new" data-ga-click="Header, create new repository">
  New repository
</a>

  <a role="menuitem" class="dropdown-item" href="https://github.com/new/import" data-ga-click="Header, import a repository">
    Import repository
  </a>

  <a role="menuitem" class="dropdown-item" href="https://github.com/codespaces/new">
    New codespace
  </a>

<a role="menuitem" class="dropdown-item" href="https://gist.github.com/" data-ga-click="Header, create new gist">
  New gist
</a>

  <a role="menuitem" class="dropdown-item" href="https://github.com/organizations/new" data-ga-click="Header, create new organization">
    New organization
  </a>



  </details-menu>
</details>

    </div>

    <div class="Header-item position-relative mr-0 d-none d-md-flex">
        
  <details class="details-overlay details-reset js-feature-preview-indicator-container" data-feature-preview-indicator-src="/users/anfreire/feature_preview/indicator_check">

  <summary class="Header-link" aria-label="View profile and more" data-analytics-event="{&quot;category&quot;:&quot;Header&quot;,&quot;action&quot;:&quot;show menu&quot;,&quot;label&quot;:&quot;icon:avatar&quot;}" aria-haspopup="menu" role="button">
    <img src="Spotify_Linux_files/100360644.jpeg" alt="@anfreire" size="20" data-view-component="true" class="avatar avatar-small circle" width="20" height="20">
      <span class="unread-indicator js-feature-preview-indicator" style="top: 1px;" hidden=""></span>
    <span class="dropdown-caret"></span>
  </summary>
  <details-menu class="dropdown-menu dropdown-menu-sw" style="width: 180px" preload="" role="menu">
      <include-fragment src="/users/100360644/menu" loading="lazy">
        <p class="text-center mt-3" data-hide-on-error="">
          <svg style="box-sizing: content-box; color: var(--color-icon-primary);" width="32" height="32" viewBox="0 0 16 16" fill="none" data-view-component="true" class="anim-rotate">
  <circle cx="8" cy="8" r="7" stroke="currentColor" stroke-opacity="0.25" stroke-width="2" vector-effect="non-scaling-stroke"></circle>
  <path d="M15 8a7.002 7.002 0 00-7-7" stroke="currentColor" stroke-width="2" stroke-linecap="round" vector-effect="non-scaling-stroke"></path>
</svg>
        </p>
        <p class="ml-1 mb-2 mt-2 color-fg-default" data-show-on-error="">
          <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-alert">
    <path d="M6.457 1.047c.659-1.234 2.427-1.234 3.086 0l6.082 11.378A1.75 1.75 0 0 1 14.082 15H1.918a1.75 1.75 0 0 1-1.543-2.575Zm1.763.707a.25.25 0 0 0-.44 0L1.698 13.132a.25.25 0 0 0 .22.368h12.164a.25.25 0 0 0 .22-.368Zm.53 3.996v2.5a.75.75 0 0 1-1.5 0v-2.5a.75.75 0 0 1 1.5 0ZM9 11a1 1 0 1 1-2 0 1 1 0 0 1 2 0Z"></path>
</svg>
          Sorry, something went wrong.
        </p>
      </include-fragment>
  </details-menu>
</details>

    </div>
</header>

          
    </div>

  <div id="start-of-content" class="show-on-focus"></div>








    <div id="js-flash-container" data-turbo-replace="">





  <template class="js-flash-template">
    
<div class="flash flash-full   {{ className }}">
  <div class="px-2">
    <button autofocus="" class="flash-close js-flash-close" type="button" aria-label="Dismiss this message">
      <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-x">
    <path d="M3.72 3.72a.75.75 0 0 1 1.06 0L8 6.94l3.22-3.22a.749.749 0 0 1 1.275.326.749.749 0 0 1-.215.734L9.06 8l3.22 3.22a.749.749 0 0 1-.326 1.275.749.749 0 0 1-.734-.215L8 9.06l-3.22 3.22a.751.751 0 0 1-1.042-.018.751.751 0 0 1-.018-1.042L6.94 8 3.72 4.78a.75.75 0 0 1 0-1.06Z"></path>
</svg>
    </button>
    <div aria-atomic="true" role="alert" class="js-flash-alert">
      
      <div>{{ message }}</div>

    </div>
  </div>
</div>
  </template>
</div>


    
    <notification-shelf-watcher data-base-url="https://github.com/notifications/beta/shelf" data-channel="eyJjIjoibm90aWZpY2F0aW9uLWNoYW5nZWQ6MTAwMzYwNjQ0IiwidCI6MTY4NTM2MzkyNX0=--56f94b37269203a7bffb56231561d672d232adcf20312eb4f6641c91ee6c5b79" data-view-component="true" class="js-socket-channel" data-refresh-delay="500" data-catalyst=""></notification-shelf-watcher>
  <div data-initial="" data-target="notification-shelf-watcher.placeholder" hidden=""></div>






      <details class="details-reset details-overlay details-overlay-dark js-command-palette-dialog" id="command-palette-pjax-container" data-turbo-replace="">
  <summary aria-label="command palette trigger" tabindex="-1" role="button"></summary>
  <details-dialog class="command-palette-details-dialog d-flex flex-column flex-justify-center height-fit" aria-label="command palette" role="dialog" aria-modal="true">
    <command-palette class="command-palette color-bg-default rounded-3 border color-shadow-small" return-to="/SpotX-CLI/SpotX-Linux/blob/main/install.sh" user-id="100360644" activation-hotkey="Mod+k,Mod+Alt+k" command-mode-hotkey="Mod+Shift+k" data-action="
        command-palette-input-ready:command-palette#inputReady
        command-palette-page-stack-updated:command-palette#updateInputScope
        itemsUpdated:command-palette#itemsUpdated
        keydown:command-palette#onKeydown
        loadingStateChanged:command-palette#loadingStateChanged
        selectedItemChanged:command-palette#selectedItemChanged
        pageFetchError:command-palette#pageFetchError
      " data-catalyst="">

        <command-palette-mode data-char="#" data-scope-types="[&quot;&quot;]" data-placeholder="Search issues and pull requests" data-catalyst=""></command-palette-mode>
        <command-palette-mode data-char="#" data-scope-types="[&quot;owner&quot;,&quot;repository&quot;]" data-placeholder="Search issues, pull requests, discussions, and projects" data-catalyst=""></command-palette-mode>
        <command-palette-mode data-char="!" data-scope-types="[&quot;owner&quot;,&quot;repository&quot;]" data-placeholder="Search projects" data-catalyst=""></command-palette-mode>
        <command-palette-mode data-char="@" data-scope-types="[&quot;&quot;]" data-placeholder="Search or jump to a user, organization, or repository" data-catalyst=""></command-palette-mode>
        <command-palette-mode data-char="@" data-scope-types="[&quot;owner&quot;]" data-placeholder="Search or jump to a repository" data-catalyst=""></command-palette-mode>
        <command-palette-mode data-char="/" data-scope-types="[&quot;repository&quot;]" data-placeholder="Search files" data-catalyst=""></command-palette-mode>
        <command-palette-mode data-char="?" data-placeholder="" data-catalyst="" data-scope-types=""></command-palette-mode>
        <command-palette-mode data-char="&gt;" data-placeholder="Run a command" data-scope-types="" data-catalyst=""></command-palette-mode>
        <command-palette-mode data-char="" data-scope-types="[&quot;&quot;]" data-placeholder="Search or jump to..." data-catalyst=""></command-palette-mode>
        <command-palette-mode data-char="" data-scope-types="[&quot;owner&quot;]" data-placeholder="Search or jump to..." data-catalyst=""></command-palette-mode>
      <command-palette-mode class="js-command-palette-default-mode" data-char="" data-placeholder="Search or jump to..." data-scope-types="" data-catalyst=""></command-palette-mode>

      <command-palette-input placeholder="Search or jump to..." data-action="
          command-palette-input:command-palette#onInput
          command-palette-select:command-palette#onSelect
          command-palette-descope:command-palette#onDescope
          command-palette-cleared:command-palette#onInputClear
        " data-catalyst="" class="d-flex flex-items-center flex-nowrap py-1 pl-3 pr-2 border-bottom">
        <div class="js-search-icon d-flex flex-items-center mr-2" style="height: 26px">
          <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-search color-fg-muted">
    <path d="M10.68 11.74a6 6 0 0 1-7.922-8.982 6 6 0 0 1 8.982 7.922l3.04 3.04a.749.749 0 0 1-.326 1.275.749.749 0 0 1-.734-.215ZM11.5 7a4.499 4.499 0 1 0-8.997 0A4.499 4.499 0 0 0 11.5 7Z"></path>
</svg>
        </div>
        <div class="js-spinner d-flex flex-items-center mr-2 color-fg-muted" hidden="">
          <svg aria-label="Loading" class="anim-rotate" viewBox="0 0 16 16" fill="none" width="16" height="16">
            <circle cx="8" cy="8" r="7" stroke="currentColor" stroke-opacity="0.25" stroke-width="2" vector-effect="non-scaling-stroke"></circle>
            <path d="M15 8a7.002 7.002 0 00-7-7" stroke="currentColor" stroke-width="2" stroke-linecap="round" vector-effect="non-scaling-stroke"></path>
          </svg>
        </div>
        <command-palette-scope data-catalyst="" class="d-inline-flex" data-small-display="">
          <div data-target="command-palette-scope.placeholder" class="color-fg-subtle">/&nbsp;&nbsp;<span class="text-semibold color-fg-default">...</span>&nbsp;&nbsp;/&nbsp;&nbsp;</div>
              
              
        
        <command-palette-token data-text="SpotX-CLI" data-id="O_kgDOBtiIYA" data-type="owner" data-value="SpotX-CLI" data-targets="command-palette-scope.tokens" class="color-fg-default text-semibold" style="white-space:nowrap;line-height:20px;" id="" data-catalyst="" hidden="">SpotX-CLI<span class="color-fg-subtle text-normal">&nbsp;&nbsp;/&nbsp;&nbsp;</span>
        </command-palette-token>
      
        <command-palette-token data-text="SpotX-Linux" data-id="R_kgDOIRWivw" data-type="repository" data-value="SpotX-Linux" data-targets="command-palette-scope.tokens" class="color-fg-default text-semibold" style="white-space:nowrap;line-height:20px;" id="" data-catalyst="">SpotX-Linux<span class="color-fg-subtle text-normal">&nbsp;&nbsp;/&nbsp;&nbsp;</span>
        </command-palette-token>
      </command-palette-scope>
        <div class="command-palette-input-group flex-1 form-control border-0 box-shadow-none" style="z-index: 0">
          <div class="command-palette-typeahead position-absolute d-flex flex-items-center Truncate">
            <span class="typeahead-segment input-mirror" data-target="command-palette-input.mirror"></span>
            <span class="Truncate-text" data-target="command-palette-input.typeaheadText"></span>
            <span class="typeahead-segment" data-target="command-palette-input.typeaheadPlaceholder"></span>
          </div>
          <input class="js-overlay-input typeahead-input d-none" disabled="disabled" tabindex="-1" aria-label="Hidden input for typeahead">
          <input type="text" autocomplete="off" autocorrect="off" autocapitalize="none" spellcheck="false" class="js-input typeahead-input form-control border-0 box-shadow-none input-block width-full no-focus-indicator" aria-label="Command palette input" aria-haspopup="listbox" aria-expanded="false" aria-autocomplete="list" aria-controls="command-palette-page-stack" role="combobox" data-action="
              input:command-palette-input#onInput
              keydown:command-palette-input#onKeydown
            " placeholder="Search or jump to...">
        </div>
          <div data-view-component="true" class="position-relative d-inline-block">
    <button aria-keyshortcuts="Control+Backspace" data-action="click:command-palette-input#onClear keypress:command-palette-input#onClear" data-target="command-palette-input.clearButton" id="command-palette-clear-button" type="button" data-view-component="true" class="btn-octicon command-palette-input-clear-button" aria-labelledby="tooltip-4f1ad310-8316-46a2-a426-f3cb498361e6" hidden="hidden">      <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-x-circle-fill">
    <path d="M2.343 13.657A8 8 0 1 1 13.658 2.343 8 8 0 0 1 2.343 13.657ZM6.03 4.97a.751.751 0 0 0-1.042.018.751.751 0 0 0-.018 1.042L6.94 8 4.97 9.97a.749.749 0 0 0 .326 1.275.749.749 0 0 0 .734-.215L8 9.06l1.97 1.97a.749.749 0 0 0 1.275-.326.749.749 0 0 0-.215-.734L9.06 8l1.97-1.97a.749.749 0 0 0-.326-1.275.749.749 0 0 0-.734.215L8 6.94Z"></path>
</svg>
</button>    <tool-tip id="tooltip-4f1ad310-8316-46a2-a426-f3cb498361e6" for="command-palette-clear-button" data-direction="w" data-type="label" data-view-component="true" class="sr-only position-absolute" aria-hidden="true" role="tooltip">Clear Command Palette</tool-tip>
</div>
      </command-palette-input>

      <command-palette-page-stack data-default-scope-id="R_kgDOIRWivw" data-default-scope-type="Repository" data-action="command-palette-page-octicons-cached:command-palette-page-stack#cacheOcticons" data-current-mode="" data-catalyst="" data-target="command-palette.pageStack" data-current-query-text="">
          <command-palette-tip class="color-fg-muted f6 px-3 py-1 my-2" data-scope-types="[&quot;&quot;,&quot;owner&quot;,&quot;repository&quot;]" data-mode="" data-value="" data-match-mode="" data-catalyst="" hidden="">
            <div class="d-flex flex-items-start flex-justify-between">
              <div>
                <span class="text-bold">Tip:</span>
                  Type <kbd class="hx_kbd">#</kbd> to search pull requests
              </div>
              <div class="ml-2 flex-shrink-0">
                Type <kbd class="hx_kbd">?</kbd> for help and tips
              </div>
            </div>
          </command-palette-tip>
          <command-palette-tip class="color-fg-muted f6 px-3 py-1 my-2" data-scope-types="[&quot;&quot;,&quot;owner&quot;,&quot;repository&quot;]" data-mode="" data-value="" data-match-mode="" data-catalyst="" hidden="">
            <div class="d-flex flex-items-start flex-justify-between">
              <div>
                <span class="text-bold">Tip:</span>
                  Type <kbd class="hx_kbd">#</kbd> to search issues
              </div>
              <div class="ml-2 flex-shrink-0">
                Type <kbd class="hx_kbd">?</kbd> for help and tips
              </div>
            </div>
          </command-palette-tip>
          <command-palette-tip class="color-fg-muted f6 px-3 py-1 my-2" data-scope-types="[&quot;owner&quot;,&quot;repository&quot;]" data-mode="" data-value="" data-match-mode="" data-catalyst="" hidden="">
            <div class="d-flex flex-items-start flex-justify-between">
              <div>
                <span class="text-bold">Tip:</span>
                  Type <kbd class="hx_kbd">#</kbd> to search discussions
              </div>
              <div class="ml-2 flex-shrink-0">
                Type <kbd class="hx_kbd">?</kbd> for help and tips
              </div>
            </div>
          </command-palette-tip>
          <command-palette-tip class="color-fg-muted f6 px-3 py-1 my-2" data-scope-types="[&quot;owner&quot;,&quot;repository&quot;]" data-mode="" data-value="" data-match-mode="" data-catalyst="" hidden="">
            <div class="d-flex flex-items-start flex-justify-between">
              <div>
                <span class="text-bold">Tip:</span>
                  Type <kbd class="hx_kbd">!</kbd> to search projects
              </div>
              <div class="ml-2 flex-shrink-0">
                Type <kbd class="hx_kbd">?</kbd> for help and tips
              </div>
            </div>
          </command-palette-tip>
          <command-palette-tip class="color-fg-muted f6 px-3 py-1 my-2" data-scope-types="[&quot;owner&quot;]" data-mode="" data-value="" data-match-mode="" data-catalyst="" hidden="">
            <div class="d-flex flex-items-start flex-justify-between">
              <div>
                <span class="text-bold">Tip:</span>
                  Type <kbd class="hx_kbd">@</kbd> to search teams
              </div>
              <div class="ml-2 flex-shrink-0">
                Type <kbd class="hx_kbd">?</kbd> for help and tips
              </div>
            </div>
          </command-palette-tip>
          <command-palette-tip class="color-fg-muted f6 px-3 py-1 my-2" data-scope-types="[&quot;&quot;]" data-mode="" data-value="" data-match-mode="" data-catalyst="" hidden="">
            <div class="d-flex flex-items-start flex-justify-between">
              <div>
                <span class="text-bold">Tip:</span>
                  Type <kbd class="hx_kbd">@</kbd> to search people and organizations
              </div>
              <div class="ml-2 flex-shrink-0">
                Type <kbd class="hx_kbd">?</kbd> for help and tips
              </div>
            </div>
          </command-palette-tip>
          <command-palette-tip class="color-fg-muted f6 px-3 py-1 my-2" data-scope-types="[&quot;&quot;,&quot;owner&quot;,&quot;repository&quot;]" data-mode="" data-value="" data-match-mode="" data-catalyst="" hidden="">
            <div class="d-flex flex-items-start flex-justify-between">
              <div>
                <span class="text-bold">Tip:</span>
                  Type <kbd class="hx_kbd">&gt;</kbd> to activate command mode
              </div>
              <div class="ml-2 flex-shrink-0">
                Type <kbd class="hx_kbd">?</kbd> for help and tips
              </div>
            </div>
          </command-palette-tip>
          <command-palette-tip class="color-fg-muted f6 px-3 py-1 my-2" data-scope-types="[&quot;&quot;,&quot;owner&quot;,&quot;repository&quot;]" data-mode="" data-value="" data-match-mode="" data-catalyst="" hidden="">
            <div class="d-flex flex-items-start flex-justify-between">
              <div>
                <span class="text-bold">Tip:</span>
                  Go to your accessibility settings to change your keyboard shortcuts
              </div>
              <div class="ml-2 flex-shrink-0">
                Type <kbd class="hx_kbd">?</kbd> for help and tips
              </div>
            </div>
          </command-palette-tip>
          <command-palette-tip class="color-fg-muted f6 px-3 py-1 my-2" data-scope-types="[&quot;&quot;,&quot;owner&quot;,&quot;repository&quot;]" data-mode="#" data-value="" data-match-mode="" data-catalyst="" hidden="">
            <div class="d-flex flex-items-start flex-justify-between">
              <div>
                <span class="text-bold">Tip:</span>
                  Type author:@me to search your content
              </div>
              <div class="ml-2 flex-shrink-0">
                Type <kbd class="hx_kbd">?</kbd> for help and tips
              </div>
            </div>
          </command-palette-tip>
          <command-palette-tip class="color-fg-muted f6 px-3 py-1 my-2" data-scope-types="[&quot;&quot;,&quot;owner&quot;,&quot;repository&quot;]" data-mode="#" data-value="" data-match-mode="" data-catalyst="" hidden="">
            <div class="d-flex flex-items-start flex-justify-between">
              <div>
                <span class="text-bold">Tip:</span>
                  Type is:pr to filter to pull requests
              </div>
              <div class="ml-2 flex-shrink-0">
                Type <kbd class="hx_kbd">?</kbd> for help and tips
              </div>
            </div>
          </command-palette-tip>
          <command-palette-tip class="color-fg-muted f6 px-3 py-1 my-2" data-scope-types="[&quot;&quot;,&quot;owner&quot;,&quot;repository&quot;]" data-mode="#" data-value="" data-match-mode="" data-catalyst="" hidden="">
            <div class="d-flex flex-items-start flex-justify-between">
              <div>
                <span class="text-bold">Tip:</span>
                  Type is:issue to filter to issues
              </div>
              <div class="ml-2 flex-shrink-0">
                Type <kbd class="hx_kbd">?</kbd> for help and tips
              </div>
            </div>
          </command-palette-tip>
          <command-palette-tip class="color-fg-muted f6 px-3 py-1 my-2" data-scope-types="[&quot;owner&quot;,&quot;repository&quot;]" data-mode="#" data-value="" data-match-mode="" data-catalyst="" hidden="">
            <div class="d-flex flex-items-start flex-justify-between">
              <div>
                <span class="text-bold">Tip:</span>
                  Type is:project to filter to projects
              </div>
              <div class="ml-2 flex-shrink-0">
                Type <kbd class="hx_kbd">?</kbd> for help and tips
              </div>
            </div>
          </command-palette-tip>
          <command-palette-tip class="color-fg-muted f6 px-3 py-1 my-2" data-scope-types="[&quot;&quot;,&quot;owner&quot;,&quot;repository&quot;]" data-mode="#" data-value="" data-match-mode="" data-catalyst="" hidden="">
            <div class="d-flex flex-items-start flex-justify-between">
              <div>
                <span class="text-bold">Tip:</span>
                  Type is:open to filter to open content
              </div>
              <div class="ml-2 flex-shrink-0">
                Type <kbd class="hx_kbd">?</kbd> for help and tips
              </div>
            </div>
          </command-palette-tip>
        <command-palette-tip class="mx-3 my-2 flash flash-error d-flex flex-items-center" data-scope-types="*" data-on-error="" data-mode="*" data-catalyst="" data-match-mode="" data-value="*" hidden="">
          <div>
            <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-alert">
    <path d="M6.457 1.047c.659-1.234 2.427-1.234 3.086 0l6.082 11.378A1.75 1.75 0 0 1 14.082 15H1.918a1.75 1.75 0 0 1-1.543-2.575Zm1.763.707a.25.25 0 0 0-.44 0L1.698 13.132a.25.25 0 0 0 .22.368h12.164a.25.25 0 0 0 .22-.368Zm.53 3.996v2.5a.75.75 0 0 1-1.5 0v-2.5a.75.75 0 0 1 1.5 0ZM9 11a1 1 0 1 1-2 0 1 1 0 0 1 2 0Z"></path>
</svg>
          </div>
          <div class="px-2">
            We’ve encountered an error and some results aren't available at this time. Type a new search or try again later.
          </div>
        </command-palette-tip>
        <command-palette-tip class="h4 color-fg-default pl-3 pb-2 pt-3" data-on-empty="" data-scope-types="*" data-match-mode="[^?]|^$" data-mode="*" data-catalyst="" data-value="*" hidden="">
          No results matched your search
        </command-palette-tip>

        <div hidden="">

            <div data-targets="command-palette-page-stack.localOcticons" data-octicon-id="arrow-right-color-fg-muted">
              <svg height="16" class="octicon octicon-arrow-right color-fg-muted" viewBox="0 0 16 16" version="1.1" width="16" aria-hidden="true"><path d="M8.22 2.97a.75.75 0 0 1 1.06 0l4.25 4.25a.75.75 0 0 1 0 1.06l-4.25 4.25a.751.751 0 0 1-1.042-.018.751.751 0 0 1-.018-1.042l2.97-2.97H3.75a.75.75 0 0 1 0-1.5h7.44L8.22 4.03a.75.75 0 0 1 0-1.06Z"></path></svg>
            </div>
            <div data-targets="command-palette-page-stack.localOcticons" data-octicon-id="arrow-right-color-fg-default">
              <svg height="16" class="octicon octicon-arrow-right color-fg-default" viewBox="0 0 16 16" version="1.1" width="16" aria-hidden="true"><path d="M8.22 2.97a.75.75 0 0 1 1.06 0l4.25 4.25a.75.75 0 0 1 0 1.06l-4.25 4.25a.751.751 0 0 1-1.042-.018.751.751 0 0 1-.018-1.042l2.97-2.97H3.75a.75.75 0 0 1 0-1.5h7.44L8.22 4.03a.75.75 0 0 1 0-1.06Z"></path></svg>
            </div>
            <div data-targets="command-palette-page-stack.localOcticons" data-octicon-id="codespaces-color-fg-muted">
              <svg height="16" class="octicon octicon-codespaces color-fg-muted" viewBox="0 0 16 16" version="1.1" width="16" aria-hidden="true"><path d="M0 11.25c0-.966.784-1.75 1.75-1.75h12.5c.966 0 1.75.784 1.75 1.75v3A1.75 1.75 0 0 1 14.25 16H1.75A1.75 1.75 0 0 1 0 14.25Zm2-9.5C2 .784 2.784 0 3.75 0h8.5C13.216 0 14 .784 14 1.75v5a1.75 1.75 0 0 1-1.75 1.75h-8.5A1.75 1.75 0 0 1 2 6.75Zm1.75-.25a.25.25 0 0 0-.25.25v5c0 .138.112.25.25.25h8.5a.25.25 0 0 0 .25-.25v-5a.25.25 0 0 0-.25-.25Zm-2 9.5a.25.25 0 0 0-.25.25v3c0 .138.112.25.25.25h12.5a.25.25 0 0 0 .25-.25v-3a.25.25 0 0 0-.25-.25Z"></path><path d="M7 12.75a.75.75 0 0 1 .75-.75h4.5a.75.75 0 0 1 0 1.5h-4.5a.75.75 0 0 1-.75-.75Zm-4 0a.75.75 0 0 1 .75-.75h.5a.75.75 0 0 1 0 1.5h-.5a.75.75 0 0 1-.75-.75Z"></path></svg>
            </div>
            <div data-targets="command-palette-page-stack.localOcticons" data-octicon-id="copy-color-fg-muted">
              <svg height="16" class="octicon octicon-copy color-fg-muted" viewBox="0 0 16 16" version="1.1" width="16" aria-hidden="true"><path d="M0 6.75C0 5.784.784 5 1.75 5h1.5a.75.75 0 0 1 0 1.5h-1.5a.25.25 0 0 0-.25.25v7.5c0 .138.112.25.25.25h7.5a.25.25 0 0 0 .25-.25v-1.5a.75.75 0 0 1 1.5 0v1.5A1.75 1.75 0 0 1 9.25 16h-7.5A1.75 1.75 0 0 1 0 14.25Z"></path><path d="M5 1.75C5 .784 5.784 0 6.75 0h7.5C15.216 0 16 .784 16 1.75v7.5A1.75 1.75 0 0 1 14.25 11h-7.5A1.75 1.75 0 0 1 5 9.25Zm1.75-.25a.25.25 0 0 0-.25.25v7.5c0 .138.112.25.25.25h7.5a.25.25 0 0 0 .25-.25v-7.5a.25.25 0 0 0-.25-.25Z"></path></svg>
            </div>
            <div data-targets="command-palette-page-stack.localOcticons" data-octicon-id="dash-color-fg-muted">
              <svg height="16" class="octicon octicon-dash color-fg-muted" viewBox="0 0 16 16" version="1.1" width="16" aria-hidden="true"><path d="M2 7.75A.75.75 0 0 1 2.75 7h10a.75.75 0 0 1 0 1.5h-10A.75.75 0 0 1 2 7.75Z"></path></svg>
            </div>
            <div data-targets="command-palette-page-stack.localOcticons" data-octicon-id="file-color-fg-muted">
              <svg height="16" class="octicon octicon-file color-fg-muted" viewBox="0 0 16 16" version="1.1" width="16" aria-hidden="true"><path d="M2 1.75C2 .784 2.784 0 3.75 0h6.586c.464 0 .909.184 1.237.513l2.914 2.914c.329.328.513.773.513 1.237v9.586A1.75 1.75 0 0 1 13.25 16h-9.5A1.75 1.75 0 0 1 2 14.25Zm1.75-.25a.25.25 0 0 0-.25.25v12.5c0 .138.112.25.25.25h9.5a.25.25 0 0 0 .25-.25V6h-2.75A1.75 1.75 0 0 1 9 4.25V1.5Zm6.75.062V4.25c0 .138.112.25.25.25h2.688l-.011-.013-2.914-2.914-.013-.011Z"></path></svg>
            </div>
            <div data-targets="command-palette-page-stack.localOcticons" data-octicon-id="gear-color-fg-muted">
              <svg height="16" class="octicon octicon-gear color-fg-muted" viewBox="0 0 16 16" version="1.1" width="16" aria-hidden="true"><path d="M8 0a8.2 8.2 0 0 1 .701.031C9.444.095 9.99.645 10.16 1.29l.288 1.107c.018.066.079.158.212.224.231.114.454.243.668.386.123.082.233.09.299.071l1.103-.303c.644-.176 1.392.021 1.82.63.27.385.506.792.704 1.218.315.675.111 1.422-.364 1.891l-.814.806c-.049.048-.098.147-.088.294.016.257.016.515 0 .772-.01.147.038.246.088.294l.814.806c.475.469.679 1.216.364 1.891a7.977 7.977 0 0 1-.704 1.217c-.428.61-1.176.807-1.82.63l-1.102-.302c-.067-.019-.177-.011-.3.071a5.909 5.909 0 0 1-.668.386c-.133.066-.194.158-.211.224l-.29 1.106c-.168.646-.715 1.196-1.458 1.26a8.006 8.006 0 0 1-1.402 0c-.743-.064-1.289-.614-1.458-1.26l-.289-1.106c-.018-.066-.079-.158-.212-.224a5.738 5.738 0 0 1-.668-.386c-.123-.082-.233-.09-.299-.071l-1.103.303c-.644.176-1.392-.021-1.82-.63a8.12 8.12 0 0 1-.704-1.218c-.315-.675-.111-1.422.363-1.891l.815-.806c.05-.048.098-.147.088-.294a6.214 6.214 0 0 1 0-.772c.01-.147-.038-.246-.088-.294l-.815-.806C.635 6.045.431 5.298.746 4.623a7.92 7.92 0 0 1 .704-1.217c.428-.61 1.176-.807 1.82-.63l1.102.302c.067.019.177.011.3-.071.214-.143.437-.272.668-.386.133-.066.194-.158.211-.224l.29-1.106C6.009.645 6.556.095 7.299.03 7.53.01 7.764 0 8 0Zm-.571 1.525c-.036.003-.108.036-.137.146l-.289 1.105c-.147.561-.549.967-.998 1.189-.173.086-.34.183-.5.29-.417.278-.97.423-1.529.27l-1.103-.303c-.109-.03-.175.016-.195.045-.22.312-.412.644-.573.99-.014.031-.021.11.059.19l.815.806c.411.406.562.957.53 1.456a4.709 4.709 0 0 0 0 .582c.032.499-.119 1.05-.53 1.456l-.815.806c-.081.08-.073.159-.059.19.162.346.353.677.573.989.02.03.085.076.195.046l1.102-.303c.56-.153 1.113-.008 1.53.27.161.107.328.204.501.29.447.222.85.629.997 1.189l.289 1.105c.029.109.101.143.137.146a6.6 6.6 0 0 0 1.142 0c.036-.003.108-.036.137-.146l.289-1.105c.147-.561.549-.967.998-1.189.173-.086.34-.183.5-.29.417-.278.97-.423 1.529-.27l1.103.303c.109.029.175-.016.195-.045.22-.313.411-.644.573-.99.014-.031.021-.11-.059-.19l-.815-.806c-.411-.406-.562-.957-.53-1.456a4.709 4.709 0 0 0 0-.582c-.032-.499.119-1.05.53-1.456l.815-.806c.081-.08.073-.159.059-.19a6.464 6.464 0 0 0-.573-.989c-.02-.03-.085-.076-.195-.046l-1.102.303c-.56.153-1.113.008-1.53-.27a4.44 4.44 0 0 0-.501-.29c-.447-.222-.85-.629-.997-1.189l-.289-1.105c-.029-.11-.101-.143-.137-.146a6.6 6.6 0 0 0-1.142 0ZM11 8a3 3 0 1 1-6 0 3 3 0 0 1 6 0ZM9.5 8a1.5 1.5 0 1 0-3.001.001A1.5 1.5 0 0 0 9.5 8Z"></path></svg>
            </div>
            <div data-targets="command-palette-page-stack.localOcticons" data-octicon-id="lock-color-fg-muted">
              <svg height="16" class="octicon octicon-lock color-fg-muted" viewBox="0 0 16 16" version="1.1" width="16" aria-hidden="true"><path d="M4 4a4 4 0 0 1 8 0v2h.25c.966 0 1.75.784 1.75 1.75v5.5A1.75 1.75 0 0 1 12.25 15h-8.5A1.75 1.75 0 0 1 2 13.25v-5.5C2 6.784 2.784 6 3.75 6H4Zm8.25 3.5h-8.5a.25.25 0 0 0-.25.25v5.5c0 .138.112.25.25.25h8.5a.25.25 0 0 0 .25-.25v-5.5a.25.25 0 0 0-.25-.25ZM10.5 6V4a2.5 2.5 0 1 0-5 0v2Z"></path></svg>
            </div>
            <div data-targets="command-palette-page-stack.localOcticons" data-octicon-id="moon-color-fg-muted">
              <svg height="16" class="octicon octicon-moon color-fg-muted" viewBox="0 0 16 16" version="1.1" width="16" aria-hidden="true"><path d="M9.598 1.591a.749.749 0 0 1 .785-.175 7.001 7.001 0 1 1-8.967 8.967.75.75 0 0 1 .961-.96 5.5 5.5 0 0 0 7.046-7.046.75.75 0 0 1 .175-.786Zm1.616 1.945a7 7 0 0 1-7.678 7.678 5.499 5.499 0 1 0 7.678-7.678Z"></path></svg>
            </div>
            <div data-targets="command-palette-page-stack.localOcticons" data-octicon-id="person-color-fg-muted">
              <svg height="16" class="octicon octicon-person color-fg-muted" viewBox="0 0 16 16" version="1.1" width="16" aria-hidden="true"><path d="M10.561 8.073a6.005 6.005 0 0 1 3.432 5.142.75.75 0 1 1-1.498.07 4.5 4.5 0 0 0-8.99 0 .75.75 0 0 1-1.498-.07 6.004 6.004 0 0 1 3.431-5.142 3.999 3.999 0 1 1 5.123 0ZM10.5 5a2.5 2.5 0 1 0-5 0 2.5 2.5 0 0 0 5 0Z"></path></svg>
            </div>
            <div data-targets="command-palette-page-stack.localOcticons" data-octicon-id="pencil-color-fg-muted">
              <svg height="16" class="octicon octicon-pencil color-fg-muted" viewBox="0 0 16 16" version="1.1" width="16" aria-hidden="true"><path d="M11.013 1.427a1.75 1.75 0 0 1 2.474 0l1.086 1.086a1.75 1.75 0 0 1 0 2.474l-8.61 8.61c-.21.21-.47.364-.756.445l-3.251.93a.75.75 0 0 1-.927-.928l.929-3.25c.081-.286.235-.547.445-.758l8.61-8.61Zm.176 4.823L9.75 4.81l-6.286 6.287a.253.253 0 0 0-.064.108l-.558 1.953 1.953-.558a.253.253 0 0 0 .108-.064Zm1.238-3.763a.25.25 0 0 0-.354 0L10.811 3.75l1.439 1.44 1.263-1.263a.25.25 0 0 0 0-.354Z"></path></svg>
            </div>
            <div data-targets="command-palette-page-stack.localOcticons" data-octicon-id="issue-opened-open">
              <svg height="16" class="octicon octicon-issue-opened open" viewBox="0 0 16 16" version="1.1" width="16" aria-hidden="true"><path d="M8 9.5a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3Z"></path><path d="M8 0a8 8 0 1 1 0 16A8 8 0 0 1 8 0ZM1.5 8a6.5 6.5 0 1 0 13 0 6.5 6.5 0 0 0-13 0Z"></path></svg>
            </div>
            <div data-targets="command-palette-page-stack.localOcticons" data-octicon-id="git-pull-request-draft-color-fg-muted">
              <svg height="16" class="octicon octicon-git-pull-request-draft color-fg-muted" viewBox="0 0 16 16" version="1.1" width="16" aria-hidden="true"><path d="M3.25 1A2.25 2.25 0 0 1 4 5.372v5.256a2.251 2.251 0 1 1-1.5 0V5.372A2.251 2.251 0 0 1 3.25 1Zm9.5 14a2.25 2.25 0 1 1 0-4.5 2.25 2.25 0 0 1 0 4.5ZM2.5 3.25a.75.75 0 1 0 1.5 0 .75.75 0 0 0-1.5 0ZM3.25 12a.75.75 0 1 0 0 1.5.75.75 0 0 0 0-1.5Zm9.5 0a.75.75 0 1 0 0 1.5.75.75 0 0 0 0-1.5ZM14 7.5a1.25 1.25 0 1 1-2.5 0 1.25 1.25 0 0 1 2.5 0Zm0-4.25a1.25 1.25 0 1 1-2.5 0 1.25 1.25 0 0 1 2.5 0Z"></path></svg>
            </div>
            <div data-targets="command-palette-page-stack.localOcticons" data-octicon-id="search-color-fg-muted">
              <svg height="16" class="octicon octicon-search color-fg-muted" viewBox="0 0 16 16" version="1.1" width="16" aria-hidden="true"><path d="M10.68 11.74a6 6 0 0 1-7.922-8.982 6 6 0 0 1 8.982 7.922l3.04 3.04a.749.749 0 0 1-.326 1.275.749.749 0 0 1-.734-.215ZM11.5 7a4.499 4.499 0 1 0-8.997 0A4.499 4.499 0 0 0 11.5 7Z"></path></svg>
            </div>
            <div data-targets="command-palette-page-stack.localOcticons" data-octicon-id="sun-color-fg-muted">
              <svg height="16" class="octicon octicon-sun color-fg-muted" viewBox="0 0 16 16" version="1.1" width="16" aria-hidden="true"><path d="M8 12a4 4 0 1 1 0-8 4 4 0 0 1 0 8Zm0-1.5a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5Zm5.657-8.157a.75.75 0 0 1 0 1.061l-1.061 1.06a.749.749 0 0 1-1.275-.326.749.749 0 0 1 .215-.734l1.06-1.06a.75.75 0 0 1 1.06 0Zm-9.193 9.193a.75.75 0 0 1 0 1.06l-1.06 1.061a.75.75 0 1 1-1.061-1.06l1.06-1.061a.75.75 0 0 1 1.061 0ZM8 0a.75.75 0 0 1 .75.75v1.5a.75.75 0 0 1-1.5 0V.75A.75.75 0 0 1 8 0ZM3 8a.75.75 0 0 1-.75.75H.75a.75.75 0 0 1 0-1.5h1.5A.75.75 0 0 1 3 8Zm13 0a.75.75 0 0 1-.75.75h-1.5a.75.75 0 0 1 0-1.5h1.5A.75.75 0 0 1 16 8Zm-8 5a.75.75 0 0 1 .75.75v1.5a.75.75 0 0 1-1.5 0v-1.5A.75.75 0 0 1 8 13Zm3.536-1.464a.75.75 0 0 1 1.06 0l1.061 1.06a.75.75 0 0 1-1.06 1.061l-1.061-1.06a.75.75 0 0 1 0-1.061ZM2.343 2.343a.75.75 0 0 1 1.061 0l1.06 1.061a.751.751 0 0 1-.018 1.042.751.751 0 0 1-1.042.018l-1.06-1.06a.75.75 0 0 1 0-1.06Z"></path></svg>
            </div>
            <div data-targets="command-palette-page-stack.localOcticons" data-octicon-id="sync-color-fg-muted">
              <svg height="16" class="octicon octicon-sync color-fg-muted" viewBox="0 0 16 16" version="1.1" width="16" aria-hidden="true"><path d="M1.705 8.005a.75.75 0 0 1 .834.656 5.5 5.5 0 0 0 9.592 2.97l-1.204-1.204a.25.25 0 0 1 .177-.427h3.646a.25.25 0 0 1 .25.25v3.646a.25.25 0 0 1-.427.177l-1.38-1.38A7.002 7.002 0 0 1 1.05 8.84a.75.75 0 0 1 .656-.834ZM8 2.5a5.487 5.487 0 0 0-4.131 1.869l1.204 1.204A.25.25 0 0 1 4.896 6H1.25A.25.25 0 0 1 1 5.75V2.104a.25.25 0 0 1 .427-.177l1.38 1.38A7.002 7.002 0 0 1 14.95 7.16a.75.75 0 0 1-1.49.178A5.5 5.5 0 0 0 8 2.5Z"></path></svg>
            </div>
            <div data-targets="command-palette-page-stack.localOcticons" data-octicon-id="trash-color-fg-muted">
              <svg height="16" class="octicon octicon-trash color-fg-muted" viewBox="0 0 16 16" version="1.1" width="16" aria-hidden="true"><path d="M11 1.75V3h2.25a.75.75 0 0 1 0 1.5H2.75a.75.75 0 0 1 0-1.5H5V1.75C5 .784 5.784 0 6.75 0h2.5C10.216 0 11 .784 11 1.75ZM4.496 6.675l.66 6.6a.25.25 0 0 0 .249.225h5.19a.25.25 0 0 0 .249-.225l.66-6.6a.75.75 0 0 1 1.492.149l-.66 6.6A1.748 1.748 0 0 1 10.595 15h-5.19a1.75 1.75 0 0 1-1.741-1.575l-.66-6.6a.75.75 0 1 1 1.492-.15ZM6.5 1.75V3h3V1.75a.25.25 0 0 0-.25-.25h-2.5a.25.25 0 0 0-.25.25Z"></path></svg>
            </div>
            <div data-targets="command-palette-page-stack.localOcticons" data-octicon-id="key-color-fg-muted">
              <svg height="16" class="octicon octicon-key color-fg-muted" viewBox="0 0 16 16" version="1.1" width="16" aria-hidden="true"><path d="M10.5 0a5.499 5.499 0 1 1-1.288 10.848l-.932.932a.749.749 0 0 1-.53.22H7v.75a.749.749 0 0 1-.22.53l-.5.5a.749.749 0 0 1-.53.22H5v.75a.749.749 0 0 1-.22.53l-.5.5a.749.749 0 0 1-.53.22h-2A1.75 1.75 0 0 1 0 14.25v-2c0-.199.079-.389.22-.53l4.932-4.932A5.5 5.5 0 0 1 10.5 0Zm-4 5.5c-.001.431.069.86.205 1.269a.75.75 0 0 1-.181.768L1.5 12.56v1.69c0 .138.112.25.25.25h1.69l.06-.06v-1.19a.75.75 0 0 1 .75-.75h1.19l.06-.06v-1.19a.75.75 0 0 1 .75-.75h1.19l1.023-1.025a.75.75 0 0 1 .768-.18A4 4 0 1 0 6.5 5.5ZM11 6a1 1 0 1 1 0-2 1 1 0 0 1 0 2Z"></path></svg>
            </div>
            <div data-targets="command-palette-page-stack.localOcticons" data-octicon-id="comment-discussion-color-fg-muted">
              <svg height="16" class="octicon octicon-comment-discussion color-fg-muted" viewBox="0 0 16 16" version="1.1" width="16" aria-hidden="true"><path d="M1.75 1h8.5c.966 0 1.75.784 1.75 1.75v5.5A1.75 1.75 0 0 1 10.25 10H7.061l-2.574 2.573A1.458 1.458 0 0 1 2 11.543V10h-.25A1.75 1.75 0 0 1 0 8.25v-5.5C0 1.784.784 1 1.75 1ZM1.5 2.75v5.5c0 .138.112.25.25.25h1a.75.75 0 0 1 .75.75v2.19l2.72-2.72a.749.749 0 0 1 .53-.22h3.5a.25.25 0 0 0 .25-.25v-5.5a.25.25 0 0 0-.25-.25h-8.5a.25.25 0 0 0-.25.25Zm13 2a.25.25 0 0 0-.25-.25h-.5a.75.75 0 0 1 0-1.5h.5c.966 0 1.75.784 1.75 1.75v5.5A1.75 1.75 0 0 1 14.25 12H14v1.543a1.458 1.458 0 0 1-2.487 1.03L9.22 12.28a.749.749 0 0 1 .326-1.275.749.749 0 0 1 .734.215l2.22 2.22v-2.19a.75.75 0 0 1 .75-.75h1a.25.25 0 0 0 .25-.25Z"></path></svg>
            </div>
            <div data-targets="command-palette-page-stack.localOcticons" data-octicon-id="bell-color-fg-muted">
              <svg height="16" class="octicon octicon-bell color-fg-muted" viewBox="0 0 16 16" version="1.1" width="16" aria-hidden="true"><path d="M8 16a2 2 0 0 0 1.985-1.75c.017-.137-.097-.25-.235-.25h-3.5c-.138 0-.252.113-.235.25A2 2 0 0 0 8 16ZM3 5a5 5 0 0 1 10 0v2.947c0 .05.015.098.042.139l1.703 2.555A1.519 1.519 0 0 1 13.482 13H2.518a1.516 1.516 0 0 1-1.263-2.36l1.703-2.554A.255.255 0 0 0 3 7.947Zm5-3.5A3.5 3.5 0 0 0 4.5 5v2.947c0 .346-.102.683-.294.97l-1.703 2.556a.017.017 0 0 0-.003.01l.001.006c0 .002.002.004.004.006l.006.004.007.001h10.964l.007-.001.006-.004.004-.006.001-.007a.017.017 0 0 0-.003-.01l-1.703-2.554a1.745 1.745 0 0 1-.294-.97V5A3.5 3.5 0 0 0 8 1.5Z"></path></svg>
            </div>
            <div data-targets="command-palette-page-stack.localOcticons" data-octicon-id="bell-slash-color-fg-muted">
              <svg height="16" class="octicon octicon-bell-slash color-fg-muted" viewBox="0 0 16 16" version="1.1" width="16" aria-hidden="true"><path d="m4.182 4.31.016.011 10.104 7.316.013.01 1.375.996a.75.75 0 1 1-.88 1.214L13.626 13H2.518a1.516 1.516 0 0 1-1.263-2.36l1.703-2.554A.255.255 0 0 0 3 7.947V5.305L.31 3.357a.75.75 0 1 1 .88-1.214Zm7.373 7.19L4.5 6.391v1.556c0 .346-.102.683-.294.97l-1.703 2.556a.017.017 0 0 0-.003.01c0 .005.002.009.005.012l.006.004.007.001ZM8 1.5c-.997 0-1.895.416-2.534 1.086A.75.75 0 1 1 4.38 1.55 5 5 0 0 1 13 5v2.373a.75.75 0 0 1-1.5 0V5A3.5 3.5 0 0 0 8 1.5ZM8 16a2 2 0 0 1-1.985-1.75c-.017-.137.097-.25.235-.25h3.5c.138 0 .252.113.235.25A2 2 0 0 1 8 16Z"></path></svg>
            </div>
            <div data-targets="command-palette-page-stack.localOcticons" data-octicon-id="paintbrush-color-fg-muted">
              <svg height="16" class="octicon octicon-paintbrush color-fg-muted" viewBox="0 0 16 16" version="1.1" width="16" aria-hidden="true"><path d="M11.134 1.535c.7-.509 1.416-.942 2.076-1.155.649-.21 1.463-.267 2.069.34.603.601.568 1.411.368 2.07-.202.668-.624 1.39-1.125 2.096-1.011 1.424-2.496 2.987-3.775 4.249-1.098 1.084-2.132 1.839-3.04 2.3a3.744 3.744 0 0 1-1.055 3.217c-.431.431-1.065.691-1.657.861-.614.177-1.294.287-1.914.357A21.151 21.151 0 0 1 .797 16H.743l.007-.75H.749L.742 16a.75.75 0 0 1-.743-.742l.743-.008-.742.007v-.054a21.25 21.25 0 0 1 .13-2.284c.067-.647.187-1.287.358-1.914.17-.591.43-1.226.86-1.657a3.746 3.746 0 0 1 3.227-1.054c.466-.893 1.225-1.907 2.314-2.982 1.271-1.255 2.833-2.75 4.245-3.777ZM1.62 13.089c-.051.464-.086.929-.104 1.395.466-.018.932-.053 1.396-.104a10.511 10.511 0 0 0 1.668-.309c.526-.151.856-.325 1.011-.48a2.25 2.25 0 1 0-3.182-3.182c-.155.155-.329.485-.48 1.01a10.515 10.515 0 0 0-.309 1.67Zm10.396-10.34c-1.224.89-2.605 2.189-3.822 3.384l1.718 1.718c1.21-1.205 2.51-2.597 3.387-3.833.47-.662.78-1.227.912-1.662.134-.444.032-.551.009-.575h-.001V1.78c-.014-.014-.113-.113-.548.027-.432.14-.995.462-1.655.942Zm-4.832 7.266-.001.001a9.859 9.859 0 0 0 1.63-1.142L7.155 7.216a9.7 9.7 0 0 0-1.161 1.607c.482.302.889.71 1.19 1.192Z"></path></svg>
            </div>

            <command-palette-item-group data-group-id="top" data-group-title="Top result" data-group-hint="" data-group-limits="{}" data-default-priority="0" data-catalyst="" class="py-2 border-top" data-skip-template="" hidden="true">
            
          <div class="d-flex flex-justify-between my-2 px-3">
            <span data-target="command-palette-item-group.header" class="color-fg-muted text-bold f6 text-normal">
              Top result
            </span>
            <span data-target="command-palette-item-group.header" class="color-fg-muted f6 text-normal">
              
            </span>
          </div>
          <div role="listbox" class="list-style-none" data-target="command-palette-item-group.list" aria-label="Top result results"></div>
        </command-palette-item-group>
            <command-palette-item-group data-group-id="commands" data-group-title="Commands" data-group-hint="Type &gt; to filter" data-group-limits="{&quot;static_items_page&quot;:50,&quot;issue&quot;:50,&quot;pull_request&quot;:50,&quot;discussion&quot;:50}" data-default-priority="1" data-catalyst="" class="py-2 border-top" data-skip-template="" hidden="true">
            
          <div class="d-flex flex-justify-between my-2 px-3">
            <span data-target="command-palette-item-group.header" class="color-fg-muted text-bold f6 text-normal">
              Commands
            </span>
            <span data-target="command-palette-item-group.header" class="color-fg-muted f6 text-normal">
              Type &gt; to filter
            </span>
          </div>
          <div role="listbox" class="list-style-none" data-target="command-palette-item-group.list" aria-label="Commands results"></div>
        </command-palette-item-group>
            <command-palette-item-group data-group-id="global_commands" data-group-title="Global Commands" data-group-hint="Type &gt; to filter" data-group-limits="{&quot;issue&quot;:0,&quot;pull_request&quot;:0,&quot;discussion&quot;:0}" data-default-priority="2" data-catalyst="" class="py-2 border-top" data-skip-template="" hidden="true">
            
          <div class="d-flex flex-justify-between my-2 px-3">
            <span data-target="command-palette-item-group.header" class="color-fg-muted text-bold f6 text-normal">
              Global Commands
            </span>
            <span data-target="command-palette-item-group.header" class="color-fg-muted f6 text-normal">
              Type &gt; to filter
            </span>
          </div>
          <div role="listbox" class="list-style-none" data-target="command-palette-item-group.list" aria-label="Global Commands results"></div>
        </command-palette-item-group>
            <command-palette-item-group data-group-id="this_page" data-group-title="This Page" data-group-hint="" data-group-limits="{}" data-default-priority="3" data-catalyst="" class="py-2 border-top" data-skip-template="" hidden="true">
            
          <div class="d-flex flex-justify-between my-2 px-3">
            <span data-target="command-palette-item-group.header" class="color-fg-muted text-bold f6 text-normal">
              This Page
            </span>
            <span data-target="command-palette-item-group.header" class="color-fg-muted f6 text-normal">
              
            </span>
          </div>
          <div role="listbox" class="list-style-none" data-target="command-palette-item-group.list" aria-label="This Page results"></div>
        </command-palette-item-group>
            <command-palette-item-group data-group-id="files" data-group-title="Files" data-group-hint="" data-group-limits="{}" data-default-priority="4" data-catalyst="" class="py-2 border-top" data-skip-template="" hidden="true">
            
          <div class="d-flex flex-justify-between my-2 px-3">
            <span data-target="command-palette-item-group.header" class="color-fg-muted text-bold f6 text-normal">
              Files
            </span>
            <span data-target="command-palette-item-group.header" class="color-fg-muted f6 text-normal">
              
            </span>
          </div>
          <div role="listbox" class="list-style-none" data-target="command-palette-item-group.list" aria-label="Files results"></div>
        </command-palette-item-group>
            <command-palette-item-group data-group-id="default" data-group-title="Default" data-group-hint="" data-group-limits="{&quot;static_items_page&quot;:50}" data-default-priority="5" data-catalyst="" class="py-2 border-top" data-skip-template="" hidden="true">
            
          <div role="listbox" class="list-style-none" data-target="command-palette-item-group.list" aria-label="Default results"></div>
        </command-palette-item-group>
            <command-palette-item-group data-group-id="pages" data-group-title="Pages" data-group-hint="" data-group-limits="{&quot;repository&quot;:10}" data-default-priority="6" data-catalyst="" class="py-2 border-top" data-skip-template="" hidden="true">
            
          <div class="d-flex flex-justify-between my-2 px-3">
            <span data-target="command-palette-item-group.header" class="color-fg-muted text-bold f6 text-normal">
              Pages
            </span>
            <span data-target="command-palette-item-group.header" class="color-fg-muted f6 text-normal">
              
            </span>
          </div>
          <div role="listbox" class="list-style-none" data-target="command-palette-item-group.list" aria-label="Pages results"></div>
        </command-palette-item-group>
            <command-palette-item-group data-group-id="access_policies" data-group-title="Access Policies" data-group-hint="" data-group-limits="{}" data-default-priority="7" data-catalyst="" class="py-2 border-top" data-skip-template="" hidden="true">
            
          <div class="d-flex flex-justify-between my-2 px-3">
            <span data-target="command-palette-item-group.header" class="color-fg-muted text-bold f6 text-normal">
              Access Policies
            </span>
            <span data-target="command-palette-item-group.header" class="color-fg-muted f6 text-normal">
              
            </span>
          </div>
          <div role="listbox" class="list-style-none" data-target="command-palette-item-group.list" aria-label="Access Policies results"></div>
        </command-palette-item-group>
            <command-palette-item-group data-group-id="organizations" data-group-title="Organizations" data-group-hint="" data-group-limits="{}" data-default-priority="8" data-catalyst="" class="py-2 border-top" data-skip-template="" hidden="true">
            
          <div class="d-flex flex-justify-between my-2 px-3">
            <span data-target="command-palette-item-group.header" class="color-fg-muted text-bold f6 text-normal">
              Organizations
            </span>
            <span data-target="command-palette-item-group.header" class="color-fg-muted f6 text-normal">
              
            </span>
          </div>
          <div role="listbox" class="list-style-none" data-target="command-palette-item-group.list" aria-label="Organizations results"></div>
        </command-palette-item-group>
            <command-palette-item-group data-group-id="repositories" data-group-title="Repositories" data-group-hint="" data-group-limits="{}" data-default-priority="9" data-catalyst="" class="py-2 border-top" data-skip-template="" hidden="true">
            
          <div class="d-flex flex-justify-between my-2 px-3">
            <span data-target="command-palette-item-group.header" class="color-fg-muted text-bold f6 text-normal">
              Repositories
            </span>
            <span data-target="command-palette-item-group.header" class="color-fg-muted f6 text-normal">
              
            </span>
          </div>
          <div role="listbox" class="list-style-none" data-target="command-palette-item-group.list" aria-label="Repositories results"></div>
        </command-palette-item-group>
            <command-palette-item-group data-group-id="references" data-group-title="Issues, pull requests, and discussions" data-group-hint="Type # to filter" data-group-limits="{}" data-default-priority="10" data-catalyst="" class="py-2 border-top" data-skip-template="" hidden="true">
            
          <div class="d-flex flex-justify-between my-2 px-3">
            <span data-target="command-palette-item-group.header" class="color-fg-muted text-bold f6 text-normal">
              Issues, pull requests, and discussions
            </span>
            <span data-target="command-palette-item-group.header" class="color-fg-muted f6 text-normal">
              Type # to filter
            </span>
          </div>
          <div role="listbox" class="list-style-none" data-target="command-palette-item-group.list" aria-label="Issues, pull requests, and discussions results"></div>
        </command-palette-item-group>
            <command-palette-item-group data-group-id="teams" data-group-title="Teams" data-group-hint="" data-group-limits="{}" data-default-priority="11" data-catalyst="" class="py-2 border-top" data-skip-template="" hidden="true">
            
          <div class="d-flex flex-justify-between my-2 px-3">
            <span data-target="command-palette-item-group.header" class="color-fg-muted text-bold f6 text-normal">
              Teams
            </span>
            <span data-target="command-palette-item-group.header" class="color-fg-muted f6 text-normal">
              
            </span>
          </div>
          <div role="listbox" class="list-style-none" data-target="command-palette-item-group.list" aria-label="Teams results"></div>
        </command-palette-item-group>
            <command-palette-item-group data-group-id="users" data-group-title="Users" data-group-hint="" data-group-limits="{}" data-default-priority="12" data-catalyst="" class="py-2 border-top" data-skip-template="" hidden="true">
            
          <div class="d-flex flex-justify-between my-2 px-3">
            <span data-target="command-palette-item-group.header" class="color-fg-muted text-bold f6 text-normal">
              Users
            </span>
            <span data-target="command-palette-item-group.header" class="color-fg-muted f6 text-normal">
              
            </span>
          </div>
          <div role="listbox" class="list-style-none" data-target="command-palette-item-group.list" aria-label="Users results"></div>
        </command-palette-item-group>
            <command-palette-item-group data-group-id="memex_projects" data-group-title="Projects" data-group-hint="" data-group-limits="{}" data-default-priority="13" data-catalyst="" class="py-2 border-top" data-skip-template="" hidden="true">
            
          <div class="d-flex flex-justify-between my-2 px-3">
            <span data-target="command-palette-item-group.header" class="color-fg-muted text-bold f6 text-normal">
              Projects
            </span>
            <span data-target="command-palette-item-group.header" class="color-fg-muted f6 text-normal">
              
            </span>
          </div>
          <div role="listbox" class="list-style-none" data-target="command-palette-item-group.list" aria-label="Projects results"></div>
        </command-palette-item-group>
            <command-palette-item-group data-group-id="projects" data-group-title="Projects (classic)" data-group-hint="" data-group-limits="{}" data-default-priority="14" data-catalyst="" class="py-2 border-top" data-skip-template="" hidden="true">
            
          <div class="d-flex flex-justify-between my-2 px-3">
            <span data-target="command-palette-item-group.header" class="color-fg-muted text-bold f6 text-normal">
              Projects (classic)
            </span>
            <span data-target="command-palette-item-group.header" class="color-fg-muted f6 text-normal">
              
            </span>
          </div>
          <div role="listbox" class="list-style-none" data-target="command-palette-item-group.list" aria-label="Projects (classic) results"></div>
        </command-palette-item-group>
            <command-palette-item-group data-group-id="footer" data-group-title="Footer" data-group-hint="" data-group-limits="{}" data-default-priority="15" data-catalyst="" class="py-2 border-top" data-skip-template="" hidden="true">
            
          <div role="listbox" class="list-style-none" data-target="command-palette-item-group.list" aria-label="Footer results"></div>
        </command-palette-item-group>
            <command-palette-item-group data-group-id="modes_help" data-group-title="Modes" data-group-hint="" data-group-limits="{}" data-default-priority="16" data-catalyst="" class="py-2 border-top" data-skip-template="" hidden="true">
            
          <div class="d-flex flex-justify-between my-2 px-3">
            <span data-target="command-palette-item-group.header" class="color-fg-muted text-bold f6 text-normal">
              Modes
            </span>
            <span data-target="command-palette-item-group.header" class="color-fg-muted f6 text-normal">
              
            </span>
          </div>
          <div role="listbox" class="list-style-none" data-target="command-palette-item-group.list" aria-label="Modes results"></div>
        </command-palette-item-group>
            <command-palette-item-group data-group-id="filters_help" data-group-title="Use filters in issues, pull requests, discussions, and projects" data-group-hint="" data-group-limits="{}" data-default-priority="17" data-catalyst="" class="py-2 border-top" data-skip-template="" hidden="true">
            
          <div class="d-flex flex-justify-between my-2 px-3">
            <span data-target="command-palette-item-group.header" class="color-fg-muted text-bold f6 text-normal">
              Use filters in issues, pull requests, discussions, and projects
            </span>
            <span data-target="command-palette-item-group.header" class="color-fg-muted f6 text-normal">
              
            </span>
          </div>
          <div role="listbox" class="list-style-none" data-target="command-palette-item-group.list" aria-label="Use filters in issues, pull requests, discussions, and projects results"></div>
        </command-palette-item-group>

            <command-palette-page data-page-title="SpotX-CLI" data-scope-id="O_kgDOBtiIYA" data-scope-type="owner" data-targets="command-palette-page-stack.defaultPages" data-catalyst="" class="rounded-bottom-2 page-stack-transition-height" style="max-height:400px;" hidden="">
            </command-palette-page>
            <command-palette-page data-page-title="SpotX-Linux" data-scope-id="R_kgDOIRWivw" data-scope-type="repository" data-targets="command-palette-page-stack.defaultPages" data-catalyst="" class="rounded-bottom-2 page-stack-transition-height" style="max-height:400px;" hidden="">
            </command-palette-page>
        </div>

        <command-palette-page data-is-root="" data-page-title="" data-catalyst="" class="rounded-bottom-2 page-stack-transition-height" data-targets="command-palette-page-stack.pages" style="max-height:400px;" data-scope-id="" data-scope-type="" hidden="">
        </command-palette-page>
          <command-palette-page data-page-title="SpotX-CLI" data-scope-id="O_kgDOBtiIYA" data-scope-type="owner" data-catalyst="" class="rounded-bottom-2 page-stack-transition-height" data-targets="command-palette-page-stack.pages" style="max-height:400px;" hidden="">
          </command-palette-page>
          <command-palette-page data-page-title="SpotX-Linux" data-scope-id="R_kgDOIRWivw" data-scope-type="repository" data-catalyst="" class="rounded-bottom-2 page-stack-transition-height" data-targets="command-palette-page-stack.pages" style="max-height:400px;" hidden="">
          </command-palette-page>
      </command-palette-page-stack>

      <server-defined-provider data-type="search-links" data-targets="command-palette.serverDefinedProviderElements" data-supported-modes="" data-catalyst="" data-fetch-debounce="" data-supported-scope-types="" data-src="" data-supports-commands=""></server-defined-provider>
      <server-defined-provider data-type="help" data-targets="command-palette.serverDefinedProviderElements" data-supported-modes="" data-catalyst="" data-fetch-debounce="" data-supported-scope-types="" data-src="" data-supports-commands="">
          <command-palette-help data-group="modes_help" data-prefix="#" data-scope-types="[&quot;&quot;]" data-catalyst="" hidden="">
            <span data-target="command-palette-help.titleElement">Search for <strong>issues</strong> and <strong>pull requests</strong></span>
              <span data-target="command-palette-help.hintElement">
                <kbd class="hx_kbd">#</kbd>
              </span>
          </command-palette-help>
          <command-palette-help data-group="modes_help" data-prefix="#" data-scope-types="[&quot;owner&quot;,&quot;repository&quot;]" data-catalyst="" hidden="">
            <span data-target="command-palette-help.titleElement">Search for <strong>issues, pull requests, discussions,</strong> and <strong>projects</strong></span>
              <span data-target="command-palette-help.hintElement">
                <kbd class="hx_kbd">#</kbd>
              </span>
          </command-palette-help>
          <command-palette-help data-group="modes_help" data-prefix="@" data-scope-types="[&quot;&quot;]" data-catalyst="" hidden="">
            <span data-target="command-palette-help.titleElement">Search for <strong>organizations, repositories,</strong> and <strong>users</strong></span>
              <span data-target="command-palette-help.hintElement">
                <kbd class="hx_kbd">@</kbd>
              </span>
          </command-palette-help>
          <command-palette-help data-group="modes_help" data-prefix="!" data-scope-types="[&quot;owner&quot;,&quot;repository&quot;]" data-catalyst="" hidden="">
            <span data-target="command-palette-help.titleElement">Search for <strong>projects</strong></span>
              <span data-target="command-palette-help.hintElement">
                <kbd class="hx_kbd">!</kbd>
              </span>
          </command-palette-help>
          <command-palette-help data-group="modes_help" data-prefix="/" data-scope-types="[&quot;repository&quot;]" data-catalyst="" hidden="">
            <span data-target="command-palette-help.titleElement">Search for <strong>files</strong></span>
              <span data-target="command-palette-help.hintElement">
                <kbd class="hx_kbd">/</kbd>
              </span>
          </command-palette-help>
          <command-palette-help data-group="modes_help" data-prefix="&gt;" data-scope-types="" data-catalyst="" hidden="">
            <span data-target="command-palette-help.titleElement">Activate <strong>command mode</strong></span>
              <span data-target="command-palette-help.hintElement">
                <kbd class="hx_kbd">&gt;</kbd>
              </span>
          </command-palette-help>
          <command-palette-help data-group="filters_help" data-prefix="# author:@me" data-scope-types="" data-catalyst="" hidden="">
            <span data-target="command-palette-help.titleElement">Search your issues, pull requests, and discussions</span>
              <span data-target="command-palette-help.hintElement">
                <kbd class="hx_kbd"># author:@me</kbd>
              </span>
          </command-palette-help>
          <command-palette-help data-group="filters_help" data-prefix="# author:@me" data-scope-types="" data-catalyst="" hidden="">
            <span data-target="command-palette-help.titleElement">Search your issues, pull requests, and discussions</span>
              <span data-target="command-palette-help.hintElement">
                <kbd class="hx_kbd"># author:@me</kbd>
              </span>
          </command-palette-help>
          <command-palette-help data-group="filters_help" data-prefix="# is:pr" data-scope-types="" data-catalyst="" hidden="">
            <span data-target="command-palette-help.titleElement">Filter to pull requests</span>
              <span data-target="command-palette-help.hintElement">
                <kbd class="hx_kbd"># is:pr</kbd>
              </span>
          </command-palette-help>
          <command-palette-help data-group="filters_help" data-prefix="# is:issue" data-scope-types="" data-catalyst="" hidden="">
            <span data-target="command-palette-help.titleElement">Filter to issues</span>
              <span data-target="command-palette-help.hintElement">
                <kbd class="hx_kbd"># is:issue</kbd>
              </span>
          </command-palette-help>
          <command-palette-help data-group="filters_help" data-prefix="# is:discussion" data-scope-types="[&quot;owner&quot;,&quot;repository&quot;]" data-catalyst="" hidden="">
            <span data-target="command-palette-help.titleElement">Filter to discussions</span>
              <span data-target="command-palette-help.hintElement">
                <kbd class="hx_kbd"># is:discussion</kbd>
              </span>
          </command-palette-help>
          <command-palette-help data-group="filters_help" data-prefix="# is:project" data-scope-types="[&quot;owner&quot;,&quot;repository&quot;]" data-catalyst="" hidden="">
            <span data-target="command-palette-help.titleElement">Filter to projects</span>
              <span data-target="command-palette-help.hintElement">
                <kbd class="hx_kbd"># is:project</kbd>
              </span>
          </command-palette-help>
          <command-palette-help data-group="filters_help" data-prefix="# is:open" data-scope-types="" data-catalyst="" hidden="">
            <span data-target="command-palette-help.titleElement">Filter to open issues, pull requests, and discussions</span>
              <span data-target="command-palette-help.hintElement">
                <kbd class="hx_kbd"># is:open</kbd>
              </span>
          </command-palette-help>
      </server-defined-provider>

        <server-defined-provider data-type="commands" data-fetch-debounce="0" data-src="/command_palette/commands" data-supported-modes="[]" data-supports-commands="" data-targets="command-palette.serverDefinedProviderElements" data-supported-scope-types="" data-catalyst=""></server-defined-provider>
        <server-defined-provider data-type="prefetched" data-fetch-debounce="0" data-src="/command_palette/jump_to_page_navigation" data-supported-modes="[&quot;&quot;]" data-supported-scope-types="[&quot;&quot;,&quot;owner&quot;,&quot;repository&quot;]" data-targets="command-palette.serverDefinedProviderElements" data-supports-commands="" data-catalyst=""></server-defined-provider>
        <server-defined-provider data-type="remote" data-fetch-debounce="200" data-src="/command_palette/issues" data-supported-modes="[&quot;#&quot;,&quot;#&quot;]" data-supported-scope-types="[&quot;owner&quot;,&quot;repository&quot;,&quot;&quot;]" data-targets="command-palette.serverDefinedProviderElements" data-supports-commands="" data-catalyst=""></server-defined-provider>
        <server-defined-provider data-type="remote" data-fetch-debounce="200" data-src="/command_palette/jump_to" data-supported-modes="[&quot;@&quot;,&quot;@&quot;]" data-supported-scope-types="[&quot;&quot;,&quot;owner&quot;]" data-targets="command-palette.serverDefinedProviderElements" data-supports-commands="" data-catalyst=""></server-defined-provider>
        <server-defined-provider data-type="remote" data-fetch-debounce="200" data-src="/command_palette/jump_to_members_only" data-supported-modes="[&quot;@&quot;,&quot;@&quot;,&quot;&quot;,&quot;&quot;]" data-supported-scope-types="[&quot;&quot;,&quot;owner&quot;]" data-targets="command-palette.serverDefinedProviderElements" data-supports-commands="" data-catalyst=""></server-defined-provider>
        <server-defined-provider data-type="prefetched" data-fetch-debounce="0" data-src="/command_palette/jump_to_members_only_prefetched" data-supported-modes="[&quot;@&quot;,&quot;@&quot;,&quot;&quot;,&quot;&quot;]" data-supported-scope-types="[&quot;&quot;,&quot;owner&quot;]" data-targets="command-palette.serverDefinedProviderElements" data-supports-commands="" data-catalyst=""></server-defined-provider>
        <server-defined-provider data-type="files" data-fetch-debounce="0" data-src="/command_palette/files" data-supported-modes="[&quot;/&quot;]" data-supported-scope-types="[&quot;repository&quot;]" data-targets="command-palette.serverDefinedProviderElements" data-supports-commands="" data-catalyst=""></server-defined-provider>
        <server-defined-provider data-type="remote" data-fetch-debounce="200" data-src="/command_palette/discussions" data-supported-modes="[&quot;#&quot;]" data-supported-scope-types="[&quot;owner&quot;,&quot;repository&quot;]" data-targets="command-palette.serverDefinedProviderElements" data-supports-commands="" data-catalyst=""></server-defined-provider>
        <server-defined-provider data-type="remote" data-fetch-debounce="200" data-src="/command_palette/projects" data-supported-modes="[&quot;#&quot;,&quot;!&quot;]" data-supported-scope-types="[&quot;owner&quot;,&quot;repository&quot;]" data-targets="command-palette.serverDefinedProviderElements" data-supports-commands="" data-catalyst=""></server-defined-provider>
        <server-defined-provider data-type="prefetched" data-fetch-debounce="0" data-src="/command_palette/recent_issues" data-supported-modes="[&quot;#&quot;,&quot;#&quot;]" data-supported-scope-types="[&quot;owner&quot;,&quot;repository&quot;,&quot;&quot;]" data-targets="command-palette.serverDefinedProviderElements" data-supports-commands="" data-catalyst=""></server-defined-provider>
        <server-defined-provider data-type="remote" data-fetch-debounce="200" data-src="/command_palette/teams" data-supported-modes="[&quot;@&quot;,&quot;&quot;]" data-supported-scope-types="[&quot;owner&quot;]" data-targets="command-palette.serverDefinedProviderElements" data-supports-commands="" data-catalyst=""></server-defined-provider>
        <server-defined-provider data-type="remote" data-fetch-debounce="200" data-src="/command_palette/name_with_owner_repository" data-supported-modes="[&quot;@&quot;,&quot;@&quot;,&quot;&quot;,&quot;&quot;]" data-supported-scope-types="[&quot;&quot;,&quot;owner&quot;]" data-targets="command-palette.serverDefinedProviderElements" data-supports-commands="" data-catalyst=""></server-defined-provider>
    <client-defined-provider data-catalyst="" data-provider-id="main-window-commands-provider" data-targets="command-palette.clientDefinedProviderElements"></client-defined-provider></command-palette>
  </details-dialog>
</details>

<div class="position-fixed bottom-0 left-0 ml-5 mb-5 js-command-palette-toasts" style="z-index: 1000">
  <div class="Toast Toast--loading" hidden="">
    <span class="Toast-icon">
      <svg class="Toast--spinner" viewBox="0 0 32 32" width="18" height="18" aria-hidden="true">
        <path fill="#959da5" d="M16 0 A16 16 0 0 0 16 32 A16 16 0 0 0 16 0 M16 4 A12 12 0 0 1 16 28 A12 12 0 0 1 16 4"></path>
        <path fill="#ffffff" d="M16 0 A16 16 0 0 1 32 16 L28 16 A12 12 0 0 0 16 4z"></path>
      </svg>
    </span>
    <span class="Toast-content"></span>
  </div>

  <div class="anim-fade-in fast Toast Toast--error" hidden="">
    <span class="Toast-icon">
      <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-stop">
    <path d="M4.47.22A.749.749 0 0 1 5 0h6c.199 0 .389.079.53.22l4.25 4.25c.141.14.22.331.22.53v6a.749.749 0 0 1-.22.53l-4.25 4.25A.749.749 0 0 1 11 16H5a.749.749 0 0 1-.53-.22L.22 11.53A.749.749 0 0 1 0 11V5c0-.199.079-.389.22-.53Zm.84 1.28L1.5 5.31v5.38l3.81 3.81h5.38l3.81-3.81V5.31L10.69 1.5ZM8 4a.75.75 0 0 1 .75.75v3.5a.75.75 0 0 1-1.5 0v-3.5A.75.75 0 0 1 8 4Zm0 8a1 1 0 1 1 0-2 1 1 0 0 1 0 2Z"></path>
</svg>
    </span>
    <span class="Toast-content"></span>
  </div>

  <div class="anim-fade-in fast Toast Toast--warning" hidden="">
    <span class="Toast-icon">
      <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-alert">
    <path d="M6.457 1.047c.659-1.234 2.427-1.234 3.086 0l6.082 11.378A1.75 1.75 0 0 1 14.082 15H1.918a1.75 1.75 0 0 1-1.543-2.575Zm1.763.707a.25.25 0 0 0-.44 0L1.698 13.132a.25.25 0 0 0 .22.368h12.164a.25.25 0 0 0 .22-.368Zm.53 3.996v2.5a.75.75 0 0 1-1.5 0v-2.5a.75.75 0 0 1 1.5 0ZM9 11a1 1 0 1 1-2 0 1 1 0 0 1 2 0Z"></path>
</svg>
    </span>
    <span class="Toast-content"></span>
  </div>


  <div class="anim-fade-in fast Toast Toast--success" hidden="">
    <span class="Toast-icon">
      <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-check">
    <path d="M13.78 4.22a.75.75 0 0 1 0 1.06l-7.25 7.25a.75.75 0 0 1-1.06 0L2.22 9.28a.751.751 0 0 1 .018-1.042.751.751 0 0 1 1.042-.018L6 10.94l6.72-6.72a.75.75 0 0 1 1.06 0Z"></path>
</svg>
    </span>
    <span class="Toast-content"></span>
  </div>

  <div class="anim-fade-in fast Toast" hidden="">
    <span class="Toast-icon">
      <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-info">
    <path d="M0 8a8 8 0 1 1 16 0A8 8 0 0 1 0 8Zm8-6.5a6.5 6.5 0 1 0 0 13 6.5 6.5 0 0 0 0-13ZM6.5 7.75A.75.75 0 0 1 7.25 7h1a.75.75 0 0 1 .75.75v2.75h.25a.75.75 0 0 1 0 1.5h-2a.75.75 0 0 1 0-1.5h.25v-2h-.25a.75.75 0 0 1-.75-.75ZM8 6a1 1 0 1 1 0-2 1 1 0 0 1 0 2Z"></path>
</svg>
    </span>
    <span class="Toast-content"></span>
  </div>
</div>


  <div class="application-main " data-commit-hovercards-enabled="" data-discussion-hovercards-enabled="" data-issue-and-pr-hovercards-enabled="">
        <div itemscope="" itemtype="http://schema.org/SoftwareSourceCode" class="">
    <main id="js-repo-pjax-container">
      
      
    

    






  
  <div id="repository-container-header" class="pt-3 hide-full-screen" style="background-color: var(--color-page-header-bg);" data-turbo-replace="">

      <div class="d-flex flex-wrap flex-justify-end mb-3  px-3 px-md-4 px-lg-5" style="gap: 1rem;">

        <div class="flex-auto min-width-0 width-fit mr-3">
            
  <div class=" d-flex flex-wrap flex-items-center wb-break-word f3 text-normal">
      <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-repo color-fg-muted mr-2">
    <path d="M2 2.5A2.5 2.5 0 0 1 4.5 0h8.75a.75.75 0 0 1 .75.75v12.5a.75.75 0 0 1-.75.75h-2.5a.75.75 0 0 1 0-1.5h1.75v-2h-8a1 1 0 0 0-.714 1.7.75.75 0 1 1-1.072 1.05A2.495 2.495 0 0 1 2 11.5Zm10.5-1h-8a1 1 0 0 0-1 1v6.708A2.486 2.486 0 0 1 4.5 9h8ZM5 12.25a.25.25 0 0 1 .25-.25h3.5a.25.25 0 0 1 .25.25v3.25a.25.25 0 0 1-.4.2l-1.45-1.087a.249.249 0 0 0-.3 0L5.4 15.7a.25.25 0 0 1-.4-.2Z"></path>
</svg>
    
    <span class="author flex-self-stretch" itemprop="author">
      <a class="url fn" rel="author" data-hovercard-type="organization" data-hovercard-url="/orgs/SpotX-CLI/hovercard" data-octo-click="hovercard-link-click" data-octo-dimensions="link_type:self" href="https://github.com/SpotX-CLI">
        SpotX-CLI
</a>    </span>
    <span class="mx-1 flex-self-stretch color-fg-muted">/</span>
    <strong itemprop="name" class="mr-2 flex-self-stretch">
      <a data-pjax="#repo-content-pjax-container" data-turbo-frame="repo-content-turbo-frame" href="https://github.com/SpotX-CLI/SpotX-Linux">SpotX-Linux</a>
    </strong>

    <span></span><span class="Label Label--secondary v-align-middle mr-1">Public</span>
  </div>


        </div>

        <div id="repository-details-container" data-turbo-replace="">
            <ul class="pagehead-actions flex-shrink-0 d-none d-md-inline" style="padding: 2px 0;">
    
      

  <li>
              <notifications-list-subscription-form data-action="notifications-dialog-label-toggled:notifications-list-subscription-form#handleDialogLabelToggle" class="f5 position-relative" data-catalyst="">
        <details class="details-reset details-overlay f5 position-relative" data-target="notifications-list-subscription-form.details" data-action="toggle:notifications-list-subscription-form#detailsToggled">

          <summary data-hydro-click="{&quot;event_type&quot;:&quot;repository.click&quot;,&quot;payload&quot;:{&quot;target&quot;:&quot;WATCH_BUTTON&quot;,&quot;repository_id&quot;:555066047,&quot;originating_url&quot;:&quot;https://github.com/notifications/555066047/watch_subscription?aria_id_prefix=repository-details&amp;button_block=false&amp;show_count=true&quot;,&quot;user_id&quot;:100360644}}" data-hydro-click-hmac="908e56002c6d05decf9c266b3ecd3cd803bfbb325972c694848037384321b006" data-ga-click="Repository, click Watch settings, action:notifications#watch_subscription" aria-label="SpotX-CLI/SpotX-Linux repository watch options" id="repository-details-watch-button" data-view-component="true" class="btn-sm btn" aria-haspopup="menu" role="button">    <span data-menu-button="">
              <span data-target="notifications-list-subscription-form.unwatchButtonCopy" hidden="">
                <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-eye">
    <path d="M8 2c1.981 0 3.671.992 4.933 2.078 1.27 1.091 2.187 2.345 2.637 3.023a1.62 1.62 0 0 1 0 1.798c-.45.678-1.367 1.932-2.637 3.023C11.67 13.008 9.981 14 8 14c-1.981 0-3.671-.992-4.933-2.078C1.797 10.83.88 9.576.43 8.898a1.62 1.62 0 0 1 0-1.798c.45-.677 1.367-1.931 2.637-3.022C4.33 2.992 6.019 2 8 2ZM1.679 7.932a.12.12 0 0 0 0 .136c.411.622 1.241 1.75 2.366 2.717C5.176 11.758 6.527 12.5 8 12.5c1.473 0 2.825-.742 3.955-1.715 1.124-.967 1.954-2.096 2.366-2.717a.12.12 0 0 0 0-.136c-.412-.621-1.242-1.75-2.366-2.717C10.824 4.242 9.473 3.5 8 3.5c-1.473 0-2.825.742-3.955 1.715-1.124.967-1.954 2.096-2.366 2.717ZM8 10a2 2 0 1 1-.001-3.999A2 2 0 0 1 8 10Z"></path>
</svg>
                Unwatch
              </span>
              <span data-target="notifications-list-subscription-form.stopIgnoringButtonCopy" hidden="">
                <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-bell-slash">
    <path d="m4.182 4.31.016.011 10.104 7.316.013.01 1.375.996a.75.75 0 1 1-.88 1.214L13.626 13H2.518a1.516 1.516 0 0 1-1.263-2.36l1.703-2.554A.255.255 0 0 0 3 7.947V5.305L.31 3.357a.75.75 0 1 1 .88-1.214Zm7.373 7.19L4.5 6.391v1.556c0 .346-.102.683-.294.97l-1.703 2.556a.017.017 0 0 0-.003.01c0 .005.002.009.005.012l.006.004.007.001ZM8 1.5c-.997 0-1.895.416-2.534 1.086A.75.75 0 1 1 4.38 1.55 5 5 0 0 1 13 5v2.373a.75.75 0 0 1-1.5 0V5A3.5 3.5 0 0 0 8 1.5ZM8 16a2 2 0 0 1-1.985-1.75c-.017-.137.097-.25.235-.25h3.5c.138 0 .252.113.235.25A2 2 0 0 1 8 16Z"></path>
</svg>
                Stop ignoring
              </span>
              <span data-target="notifications-list-subscription-form.watchButtonCopy">
                <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-eye">
    <path d="M8 2c1.981 0 3.671.992 4.933 2.078 1.27 1.091 2.187 2.345 2.637 3.023a1.62 1.62 0 0 1 0 1.798c-.45.678-1.367 1.932-2.637 3.023C11.67 13.008 9.981 14 8 14c-1.981 0-3.671-.992-4.933-2.078C1.797 10.83.88 9.576.43 8.898a1.62 1.62 0 0 1 0-1.798c.45-.677 1.367-1.931 2.637-3.022C4.33 2.992 6.019 2 8 2ZM1.679 7.932a.12.12 0 0 0 0 .136c.411.622 1.241 1.75 2.366 2.717C5.176 11.758 6.527 12.5 8 12.5c1.473 0 2.825-.742 3.955-1.715 1.124-.967 1.954-2.096 2.366-2.717a.12.12 0 0 0 0-.136c-.412-.621-1.242-1.75-2.366-2.717C10.824 4.242 9.473 3.5 8 3.5c-1.473 0-2.825.742-3.955 1.715-1.124.967-1.954 2.096-2.366 2.717ZM8 10a2 2 0 1 1-.001-3.999A2 2 0 0 1 8 10Z"></path>
</svg>
                Watch
              </span>
            </span>
              <span id="repo-notifications-counter" data-target="notifications-list-subscription-form.socialCount" data-pjax-replace="true" data-turbo-replace="true" title="11" data-view-component="true" class="Counter">11</span>
            <span class="dropdown-caret"></span>
</summary>
          <details-menu class="SelectMenu  " role="menu" data-target="notifications-list-subscription-form.menu">
            <div class="SelectMenu-modal notifications-component-menu-modal">
              <header class="SelectMenu-header">
                <h3 class="SelectMenu-title">Notifications</h3>
                <button class="SelectMenu-closeButton" type="button" aria-label="Close menu" data-action="click:notifications-list-subscription-form#closeMenu">
                  <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-x">
    <path d="M3.72 3.72a.75.75 0 0 1 1.06 0L8 6.94l3.22-3.22a.749.749 0 0 1 1.275.326.749.749 0 0 1-.215.734L9.06 8l3.22 3.22a.749.749 0 0 1-.326 1.275.749.749 0 0 1-.734-.215L8 9.06l-3.22 3.22a.751.751 0 0 1-1.042-.018.751.751 0 0 1-.018-1.042L6.94 8 3.72 4.78a.75.75 0 0 1 0-1.06Z"></path>
</svg>
                </button>
              </header>

              <div class="SelectMenu-list">
                <!-- '"` --><!-- </textarea></xmp> --><form data-target="notifications-list-subscription-form.form" data-action="submit:notifications-list-subscription-form#submitForm" data-turbo="false" action="/notifications/subscribe" accept-charset="UTF-8" method="post"><input type="hidden" name="authenticity_token" value="v7duUAkFLpwwelHnm1CJyCmlOMOoUVIlCVTEstd69XRXRhlR9yvkwDV1n3nOySTqIPQVY07dHxtuoMNsQdGFIQ" autocomplete="off">

                  <input type="hidden" name="repository_id" value="555066047">

                  <button type="submit" name="do" value="included" class="SelectMenu-item flex-items-start" role="menuitemradio" aria-checked="true" data-targets="notifications-list-subscription-form.subscriptionButtons">
                    <span class="f5">
                      <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-check SelectMenu-icon SelectMenu-icon--check">
    <path d="M13.78 4.22a.75.75 0 0 1 0 1.06l-7.25 7.25a.75.75 0 0 1-1.06 0L2.22 9.28a.751.751 0 0 1 .018-1.042.751.751 0 0 1 1.042-.018L6 10.94l6.72-6.72a.75.75 0 0 1 1.06 0Z"></path>
</svg>
                    </span>
                    <div>
                      <div class="f5 text-bold">
                        Participating and @mentions
                      </div>
                      <div class="text-small color-fg-muted text-normal pb-1">
                        Only receive notifications from this repository when participating or @mentioned.
                      </div>
                    </div>
                  </button>

                  <button type="submit" name="do" value="subscribed" class="SelectMenu-item flex-items-start" role="menuitemradio" aria-checked="false" data-targets="notifications-list-subscription-form.subscriptionButtons">
                    <span class="f5">
                      <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-check SelectMenu-icon SelectMenu-icon--check">
    <path d="M13.78 4.22a.75.75 0 0 1 0 1.06l-7.25 7.25a.75.75 0 0 1-1.06 0L2.22 9.28a.751.751 0 0 1 .018-1.042.751.751 0 0 1 1.042-.018L6 10.94l6.72-6.72a.75.75 0 0 1 1.06 0Z"></path>
</svg>
                    </span>
                    <div>
                      <div class="f5 text-bold">
                        All Activity
                      </div>
                      <div class="text-small color-fg-muted text-normal pb-1">
                        Notified of all notifications on this repository.
                      </div>
                    </div>
                  </button>

                  <button type="submit" name="do" value="ignore" class="SelectMenu-item flex-items-start" role="menuitemradio" aria-checked="false" data-targets="notifications-list-subscription-form.subscriptionButtons">
                    <span class="f5">
                      <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-check SelectMenu-icon SelectMenu-icon--check">
    <path d="M13.78 4.22a.75.75 0 0 1 0 1.06l-7.25 7.25a.75.75 0 0 1-1.06 0L2.22 9.28a.751.751 0 0 1 .018-1.042.751.751 0 0 1 1.042-.018L6 10.94l6.72-6.72a.75.75 0 0 1 1.06 0Z"></path>
</svg>
                    </span>
                    <div>
                      <div class="f5 text-bold">
                        Ignore
                      </div>
                      <div class="text-small color-fg-muted text-normal pb-1">
                        Never be notified.
                      </div>
                    </div>
                  </button>
</form>
                <button class="SelectMenu-item flex-items-start pr-3" type="button" role="menuitemradio" data-target="notifications-list-subscription-form.customButton" data-action="click:notifications-list-subscription-form#openCustomDialog" aria-haspopup="true" aria-checked="false">
                  <span class="f5">
                    <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-check SelectMenu-icon SelectMenu-icon--check">
    <path d="M13.78 4.22a.75.75 0 0 1 0 1.06l-7.25 7.25a.75.75 0 0 1-1.06 0L2.22 9.28a.751.751 0 0 1 .018-1.042.751.751 0 0 1 1.042-.018L6 10.94l6.72-6.72a.75.75 0 0 1 1.06 0Z"></path>
</svg>
                  </span>
                  <div>
                    <div class="d-flex flex-items-start flex-justify-between">
                      <div class="f5 text-bold">Custom</div>
                      <div class="f5 pr-1">
                        <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-arrow-right">
    <path d="M8.22 2.97a.75.75 0 0 1 1.06 0l4.25 4.25a.75.75 0 0 1 0 1.06l-4.25 4.25a.751.751 0 0 1-1.042-.018.751.751 0 0 1-.018-1.042l2.97-2.97H3.75a.75.75 0 0 1 0-1.5h7.44L8.22 4.03a.75.75 0 0 1 0-1.06Z"></path>
</svg>
                      </div>
                    </div>
                    <div class="text-small color-fg-muted text-normal pb-1">
                      Select events you want to be notified of in addition to participating and @mentions.
                    </div>
                  </div>
                </button>

              </div>
            </div>
          </details-menu>

          <details-dialog class="notifications-component-dialog " data-target="notifications-list-subscription-form.customDialog" aria-label="Custom dialog" role="dialog" aria-modal="true" hidden="">
            <div class="SelectMenu-modal notifications-component-dialog-modal overflow-visible">
              <!-- '"` --><!-- </textarea></xmp> --><form data-target="notifications-list-subscription-form.customform" data-action="submit:notifications-list-subscription-form#submitCustomForm" data-turbo="false" action="/notifications/subscribe" accept-charset="UTF-8" method="post"><input type="hidden" name="authenticity_token" value="ntkJW7rc14khUde0KynH40uMZ9f_CA7tQ7DSgW9rpZ12KH5aRPId1SReGSp-sGrBQt1KdxmEQ9MkRNVf-cDVyA" autocomplete="off">

                <input type="hidden" name="repository_id" value="555066047">

                <header class="d-sm-none SelectMenu-header pb-0 border-bottom-0 px-2 px-sm-3">
                  <h1 class="f3 SelectMenu-title d-inline-flex">
                    <button class="color-bg-default border-0 px-2 py-0 m-0 Link--secondary f5" aria-label="Return to menu" type="button" data-action="click:notifications-list-subscription-form#closeCustomDialog">
                      <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-arrow-left">
    <path d="M7.78 12.53a.75.75 0 0 1-1.06 0L2.47 8.28a.75.75 0 0 1 0-1.06l4.25-4.25a.751.751 0 0 1 1.042.018.751.751 0 0 1 .018 1.042L4.81 7h7.44a.75.75 0 0 1 0 1.5H4.81l2.97 2.97a.75.75 0 0 1 0 1.06Z"></path>
</svg>
                    </button>
                    Custom
                  </h1>
                </header>

                <header class="d-none d-sm-flex flex-items-start pt-1">
                  <button class="border-0 px-2 pt-1 m-0 Link--secondary f5" style="background-color: transparent;" aria-label="Return to menu" type="button" data-action="click:notifications-list-subscription-form#closeCustomDialog">
                    <svg style="position: relative; left: 2px; top: 1px" aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-arrow-left">
    <path d="M7.78 12.53a.75.75 0 0 1-1.06 0L2.47 8.28a.75.75 0 0 1 0-1.06l4.25-4.25a.751.751 0 0 1 1.042.018.751.751 0 0 1 .018 1.042L4.81 7h7.44a.75.75 0 0 1 0 1.5H4.81l2.97 2.97a.75.75 0 0 1 0 1.06Z"></path>
</svg>
                  </button>

                  <h1 class="pt-1 pr-4 pb-0 pl-0 f5 text-bold">
                    Custom
                  </h1>
                </header>

                <fieldset>
                  <legend>
                    <div class="text-small color-fg-muted pt-0 pr-3 pb-3 pl-6 pl-sm-5 border-bottom mb-3">
                      Select events you want to be notified of in addition to participating and @mentions.
                    </div>
                  </legend>
                  <div data-target="notifications-list-subscription-form.labelInputs">
                  </div>
                    <div class="form-checkbox mr-3 ml-6 ml-sm-5 mb-2 mt-0">
                      <label class="f5 text-normal">
                        <input type="checkbox" name="thread_types[]" value="Issue" data-targets="notifications-list-subscription-form.threadTypeCheckboxes" data-action="change:notifications-list-subscription-form#threadTypeCheckboxesUpdated">
                        Issues
                      </label>


                    </div>
                    <div class="form-checkbox mr-3 ml-6 ml-sm-5 mb-2 mt-0">
                      <label class="f5 text-normal">
                        <input type="checkbox" name="thread_types[]" value="PullRequest" data-targets="notifications-list-subscription-form.threadTypeCheckboxes" data-action="change:notifications-list-subscription-form#threadTypeCheckboxesUpdated">
                        Pull requests
                      </label>


                    </div>
                    <div class="form-checkbox mr-3 ml-6 ml-sm-5 mb-2 mt-0">
                      <label class="f5 text-normal">
                        <input type="checkbox" name="thread_types[]" value="Release" data-targets="notifications-list-subscription-form.threadTypeCheckboxes" data-action="change:notifications-list-subscription-form#threadTypeCheckboxesUpdated">
                        Releases
                      </label>


                    </div>
                    <div class="form-checkbox mr-3 ml-6 ml-sm-5 mb-2 mt-0">
                      <label class="f5 text-normal">
                        <input type="checkbox" name="thread_types[]" value="Discussion" data-targets="notifications-list-subscription-form.threadTypeCheckboxes" data-action="change:notifications-list-subscription-form#threadTypeCheckboxesUpdated">
                        Discussions
                      </label>


                    </div>
                    <div class="form-checkbox mr-3 ml-6 ml-sm-5 mb-2 mt-0">
                      <label class="f5 text-normal">
                        <input type="checkbox" name="thread_types[]" value="SecurityAlert" data-targets="notifications-list-subscription-form.threadTypeCheckboxes" data-action="change:notifications-list-subscription-form#threadTypeCheckboxesUpdated">
                        Security alerts
                      </label>


                    </div>
                </fieldset>
                <div class="pt-2 pb-3 px-3 d-flex flex-justify-start flex-row-reverse">
                    <button name="do" value="custom" data-target="notifications-list-subscription-form.customSubmit" disabled="disabled" type="submit" data-view-component="true" class="btn-primary btn-sm btn ml-2">    Apply
</button>

                    <button data-action="click:notifications-list-subscription-form#resetForm" data-close-dialog="" type="button" data-view-component="true" class="btn-sm btn">    Cancel
</button>
                </div>
</form>            </div>
          </details-dialog>


          <div class="notifications-component-dialog-overlay"></div>
        </details>
      </notifications-list-subscription-form>



  </li>

  <li>
        <div data-view-component="true" class="d-flex">
        <div data-view-component="true" class="position-relative d-inline-block">
    <a icon="repo-forked" id="fork-button" href="https://github.com/SpotX-CLI/SpotX-Linux/fork" data-hydro-click="{&quot;event_type&quot;:&quot;repository.click&quot;,&quot;payload&quot;:{&quot;target&quot;:&quot;FORK_BUTTON&quot;,&quot;repository_id&quot;:555066047,&quot;originating_url&quot;:&quot;https://github.com/SpotX-CLI/SpotX-Linux/blob/main/install.sh&quot;,&quot;user_id&quot;:100360644}}" data-hydro-click-hmac="d482e6920a7f454d8d7b25685d48afe6dbd0892271137a7375cde868b6fe5ade" data-ga-click="Repository, show fork modal, action:blob#show; text:Fork" data-view-component="true" class="btn-sm btn BtnGroup-item border-right-0" aria-describedby="tooltip-0c52481a-252f-43a5-9bad-b4f561df2888">      <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-repo-forked mr-2">
    <path d="M5 5.372v.878c0 .414.336.75.75.75h4.5a.75.75 0 0 0 .75-.75v-.878a2.25 2.25 0 1 1 1.5 0v.878a2.25 2.25 0 0 1-2.25 2.25h-1.5v2.128a2.251 2.251 0 1 1-1.5 0V8.5h-1.5A2.25 2.25 0 0 1 3.5 6.25v-.878a2.25 2.25 0 1 1 1.5 0ZM5 3.25a.75.75 0 1 0-1.5 0 .75.75 0 0 0 1.5 0Zm6.75.75a.75.75 0 1 0 0-1.5.75.75 0 0 0 0 1.5Zm-3 8.75a.75.75 0 1 0-1.5 0 .75.75 0 0 0 1.5 0Z"></path>
</svg>Fork
          <span id="repo-network-counter" data-pjax-replace="true" data-turbo-replace="true" title="18" data-view-component="true" class="Counter">18</span>
</a>    <tool-tip id="tooltip-0c52481a-252f-43a5-9bad-b4f561df2888" for="fork-button" data-direction="s" data-type="description" data-view-component="true" class="sr-only position-absolute" role="tooltip">Fork your own copy of SpotX-CLI/SpotX-Linux</tool-tip>
</div>
      <details group_item="true" id="my-forks-menu-555066047" data-view-component="true" class="details-reset details-overlay BtnGroup-parent d-inline-block position-relative">
              <summary aria-label="See your forks of this repository" data-view-component="true" class="btn-sm btn BtnGroup-item px-2 float-none" aria-haspopup="menu" role="button">    <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-triangle-down">
    <path d="m4.427 7.427 3.396 3.396a.25.25 0 0 0 .354 0l3.396-3.396A.25.25 0 0 0 11.396 7H4.604a.25.25 0 0 0-.177.427Z"></path>
</svg>
</summary>
  <details-menu class="SelectMenu right-0" src="/SpotX-CLI/SpotX-Linux/my_forks_menu_content?can_fork=true" role="menu">
    <div class="SelectMenu-modal">
        <button class="SelectMenu-closeButton position-absolute right-0 m-2" type="button" aria-label="Close menu" data-toggle-for="details-be8f66">
          <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-x">
    <path d="M3.72 3.72a.75.75 0 0 1 1.06 0L8 6.94l3.22-3.22a.749.749 0 0 1 1.275.326.749.749 0 0 1-.215.734L9.06 8l3.22 3.22a.749.749 0 0 1-.326 1.275.749.749 0 0 1-.734-.215L8 9.06l-3.22 3.22a.751.751 0 0 1-1.042-.018.751.751 0 0 1-.018-1.042L6.94 8 3.72 4.78a.75.75 0 0 1 0-1.06Z"></path>
</svg>
        </button>
      <div id="filter-menu-be8f66" class="d-flex flex-column flex-1 overflow-hidden">
        <div class="SelectMenu-list">

            <include-fragment class="SelectMenu-loading" aria-label="Loading">
              <svg role="menuitem" style="box-sizing: content-box; color: var(--color-icon-primary);" width="32" height="32" viewBox="0 0 16 16" fill="none" data-view-component="true" class="anim-rotate">
  <circle cx="8" cy="8" r="7" stroke="currentColor" stroke-opacity="0.25" stroke-width="2" vector-effect="non-scaling-stroke"></circle>
  <path d="M15 8a7.002 7.002 0 00-7-7" stroke="currentColor" stroke-width="2" stroke-linecap="round" vector-effect="non-scaling-stroke"></path>
</svg>
            </include-fragment>
        </div>
        
      </div>
    </div>
  </details-menu>
</details></div>
  </li>

  <li>
        <template class="js-unstar-confirmation-dialog-template">
  <div class="Box-header">
    <h2 class="Box-title">Unstar this repository?</h2>
  </div>
  <div class="Box-body">
    <p class="mb-3">
      This will remove {{ repoNameWithOwner }} from the {{ listsWithCount }} that it's been added to.
    </p>
    <div class="form-actions">
      <!-- '"` --><!-- </textarea></xmp> --><form class="js-social-confirmation-form" data-turbo="false" action="{{ confirmUrl }}" accept-charset="UTF-8" method="post">
        <input type="hidden" name="authenticity_token" value="{{ confirmCsrfToken }}">
        <input type="hidden" name="confirm" value="true">
          <button data-close-dialog="true" type="submit" data-view-component="true" class="btn-danger btn width-full">    Unstar
</button>
</form>    </div>
  </div>
</template>

  <div data-view-component="true" class="js-toggler-container js-social-container starring-container d-flex">
    <div data-view-component="true" class="starred BtnGroup flex-1">
      <!-- '"` --><!-- </textarea></xmp> --><form class="js-social-form BtnGroup-parent flex-auto js-deferred-toggler-target" data-turbo="false" action="/SpotX-CLI/SpotX-Linux/unstar" accept-charset="UTF-8" method="post"><input type="hidden" name="authenticity_token" value="kcBMgGkQBoDQOMA6K0oXPhGnO9sveKY5KRRVAxvwblivQ5hyWkqobqqBv_mwtDSYFLenT-KEVm33Pipkbd88rg" autocomplete="off">
          <input type="hidden" value="QGb-2EyLrJ3w6YF9xuQXnXUnYoBFTTpLmaqIal-qtWJ-5Soqf9ECc4pQ_r5dGjQ7cDf-FIixyh9HgPcNKYXnlA" data-csrf="true" class="js-confirm-csrf-token">
        <input type="hidden" name="context" value="repository">
          <button data-hydro-click="{&quot;event_type&quot;:&quot;repository.click&quot;,&quot;payload&quot;:{&quot;target&quot;:&quot;UNSTAR_BUTTON&quot;,&quot;repository_id&quot;:555066047,&quot;originating_url&quot;:&quot;https://github.com/SpotX-CLI/SpotX-Linux/blob/main/install.sh&quot;,&quot;user_id&quot;:100360644}}" data-hydro-click-hmac="326ab52ff654c9ae090af1f73d003df5f5782bbb59932b3483c26718b173b114" data-ga-click="Repository, click unstar button, action:blob#show; text:Unstar" aria-label="Unstar this repository (425)" type="submit" data-view-component="true" class="rounded-left-2 btn-sm btn BtnGroup-item">    <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-star-fill starred-button-icon d-inline-block mr-2">
    <path d="M8 .25a.75.75 0 0 1 .673.418l1.882 3.815 4.21.612a.75.75 0 0 1 .416 1.279l-3.046 2.97.719 4.192a.751.751 0 0 1-1.088.791L8 12.347l-3.766 1.98a.75.75 0 0 1-1.088-.79l.72-4.194L.818 6.374a.75.75 0 0 1 .416-1.28l4.21-.611L7.327.668A.75.75 0 0 1 8 .25Z"></path>
</svg><span data-view-component="true" class="d-inline">
              Starred
</span>              <span id="repo-stars-counter-unstar" aria-label="425 users starred this repository" data-singular-suffix="user starred this repository" data-plural-suffix="users starred this repository" data-turbo-replace="true" title="425" data-view-component="true" class="Counter js-social-count">425</span>
</button></form>        <details id="details-user-list-555066047-starred" data-view-component="true" class="details-reset details-overlay BtnGroup-parent js-user-list-menu d-inline-block position-relative">
        <summary aria-label="Add this repository to a list" data-view-component="true" class="btn-sm btn BtnGroup-item px-2 float-none" aria-haspopup="menu" role="button">    <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-triangle-down">
    <path d="m4.427 7.427 3.396 3.396a.25.25 0 0 0 .354 0l3.396-3.396A.25.25 0 0 0 11.396 7H4.604a.25.25 0 0 0-.177.427Z"></path>
</svg>
</summary>
  <details-menu class="SelectMenu right-0" src="/SpotX-CLI/SpotX-Linux/lists" role="menu">
    <div class="SelectMenu-modal">
        <button class="SelectMenu-closeButton position-absolute right-0 m-2" type="button" aria-label="Close menu" data-toggle-for="details-bb733d">
          <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-x">
    <path d="M3.72 3.72a.75.75 0 0 1 1.06 0L8 6.94l3.22-3.22a.749.749 0 0 1 1.275.326.749.749 0 0 1-.215.734L9.06 8l3.22 3.22a.749.749 0 0 1-.326 1.275.749.749 0 0 1-.734-.215L8 9.06l-3.22 3.22a.751.751 0 0 1-1.042-.018.751.751 0 0 1-.018-1.042L6.94 8 3.72 4.78a.75.75 0 0 1 0-1.06Z"></path>
</svg>
        </button>
      <div id="filter-menu-bb733d" class="d-flex flex-column flex-1 overflow-hidden">
        <div class="SelectMenu-list">

            <include-fragment class="SelectMenu-loading" aria-label="Loading">
              <svg role="menuitem" style="box-sizing: content-box; color: var(--color-icon-primary);" width="32" height="32" viewBox="0 0 16 16" fill="none" data-view-component="true" class="anim-rotate">
  <circle cx="8" cy="8" r="7" stroke="currentColor" stroke-opacity="0.25" stroke-width="2" vector-effect="non-scaling-stroke"></circle>
  <path d="M15 8a7.002 7.002 0 00-7-7" stroke="currentColor" stroke-width="2" stroke-linecap="round" vector-effect="non-scaling-stroke"></path>
</svg>
            </include-fragment>
        </div>
        
      </div>
    </div>
  </details-menu>
</details>
</div>
    <div data-view-component="true" class="unstarred BtnGroup flex-1">
      <!-- '"` --><!-- </textarea></xmp> --><form class="js-social-form BtnGroup-parent flex-auto" data-turbo="false" action="/SpotX-CLI/SpotX-Linux/star" accept-charset="UTF-8" method="post"><input type="hidden" name="authenticity_token" value="hQeIMhy-QoG8KupeBBJXreFpRk9RmD24pIxNyh3VVL9HwR4O-s4sJ7ImYL9vlLbpdnZ609SBq4rRHw088VBfag" autocomplete="off">
        <input type="hidden" name="context" value="repository">
          <button data-hydro-click="{&quot;event_type&quot;:&quot;repository.click&quot;,&quot;payload&quot;:{&quot;target&quot;:&quot;STAR_BUTTON&quot;,&quot;repository_id&quot;:555066047,&quot;originating_url&quot;:&quot;https://github.com/SpotX-CLI/SpotX-Linux/blob/main/install.sh&quot;,&quot;user_id&quot;:100360644}}" data-hydro-click-hmac="84dcfd90b284715d50d87b187b811ee37eaae3c11bd6ff88f54e58c32d1c6d48" data-ga-click="Repository, click star button, action:blob#show; text:Star" aria-label="Star this repository (425)" type="submit" data-view-component="true" class="js-toggler-target rounded-left-2 btn-sm btn BtnGroup-item">    <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-star d-inline-block mr-2">
    <path d="M8 .25a.75.75 0 0 1 .673.418l1.882 3.815 4.21.612a.75.75 0 0 1 .416 1.279l-3.046 2.97.719 4.192a.751.751 0 0 1-1.088.791L8 12.347l-3.766 1.98a.75.75 0 0 1-1.088-.79l.72-4.194L.818 6.374a.75.75 0 0 1 .416-1.28l4.21-.611L7.327.668A.75.75 0 0 1 8 .25Zm0 2.445L6.615 5.5a.75.75 0 0 1-.564.41l-3.097.45 2.24 2.184a.75.75 0 0 1 .216.664l-.528 3.084 2.769-1.456a.75.75 0 0 1 .698 0l2.77 1.456-.53-3.084a.75.75 0 0 1 .216-.664l2.24-2.183-3.096-.45a.75.75 0 0 1-.564-.41L8 2.694Z"></path>
</svg><span data-view-component="true" class="d-inline">
              Star
</span>              <span id="repo-stars-counter-star" aria-label="425 users starred this repository" data-singular-suffix="user starred this repository" data-plural-suffix="users starred this repository" data-turbo-replace="true" title="425" data-view-component="true" class="Counter js-social-count">425</span>
</button></form>        <details id="details-user-list-555066047-unstarred" data-view-component="true" class="details-reset details-overlay BtnGroup-parent js-user-list-menu d-inline-block position-relative">
        <summary aria-label="Add this repository to a list" data-view-component="true" class="btn-sm btn BtnGroup-item px-2 float-none" aria-haspopup="menu" role="button">    <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-triangle-down">
    <path d="m4.427 7.427 3.396 3.396a.25.25 0 0 0 .354 0l3.396-3.396A.25.25 0 0 0 11.396 7H4.604a.25.25 0 0 0-.177.427Z"></path>
</svg>
</summary>
  <details-menu class="SelectMenu right-0" src="/SpotX-CLI/SpotX-Linux/lists" role="menu">
    <div class="SelectMenu-modal">
        <button class="SelectMenu-closeButton position-absolute right-0 m-2" type="button" aria-label="Close menu" data-toggle-for="details-1efaac">
          <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-x">
    <path d="M3.72 3.72a.75.75 0 0 1 1.06 0L8 6.94l3.22-3.22a.749.749 0 0 1 1.275.326.749.749 0 0 1-.215.734L9.06 8l3.22 3.22a.749.749 0 0 1-.326 1.275.749.749 0 0 1-.734-.215L8 9.06l-3.22 3.22a.751.751 0 0 1-1.042-.018.751.751 0 0 1-.018-1.042L6.94 8 3.72 4.78a.75.75 0 0 1 0-1.06Z"></path>
</svg>
        </button>
      <div id="filter-menu-1efaac" class="d-flex flex-column flex-1 overflow-hidden">
        <div class="SelectMenu-list">

            <include-fragment class="SelectMenu-loading" aria-label="Loading">
              <svg role="menuitem" style="box-sizing: content-box; color: var(--color-icon-primary);" width="32" height="32" viewBox="0 0 16 16" fill="none" data-view-component="true" class="anim-rotate">
  <circle cx="8" cy="8" r="7" stroke="currentColor" stroke-opacity="0.25" stroke-width="2" vector-effect="non-scaling-stroke"></circle>
  <path d="M15 8a7.002 7.002 0 00-7-7" stroke="currentColor" stroke-width="2" stroke-linecap="round" vector-effect="non-scaling-stroke"></path>
</svg>
            </include-fragment>
        </div>
        
      </div>
    </div>
  </details-menu>
</details>
</div></div>
  </li>


    

</ul>

        </div>
      </div>

        <div id="responsive-meta-container" data-turbo-replace="">
</div>


          <nav data-pjax="#js-repo-pjax-container" aria-label="Repository" data-view-component="true" class="js-repo-nav js-sidenav-container-pjax js-responsive-underlinenav overflow-hidden UnderlineNav px-3 px-md-4 px-lg-5">

  <ul data-view-component="true" class="UnderlineNav-body list-style-none">
      <li data-view-component="true" class="d-inline-flex">
  <a id="code-tab" href="https://github.com/SpotX-CLI/SpotX-Linux" data-tab-item="i0code-tab" data-selected-links="repo_source repo_downloads repo_commits repo_releases repo_tags repo_branches repo_packages repo_deployments /SpotX-CLI/SpotX-Linux" data-pjax="#repo-content-pjax-container" data-turbo-frame="repo-content-turbo-frame" data-hotkey="g c" data-analytics-event="{&quot;category&quot;:&quot;Underline navbar&quot;,&quot;action&quot;:&quot;Click tab&quot;,&quot;label&quot;:&quot;Code&quot;,&quot;target&quot;:&quot;UNDERLINE_NAV.TAB&quot;}" aria-current="page" data-view-component="true" class="UnderlineNav-item no-wrap js-responsive-underlinenav-item js-selected-navigation-item selected">
    
              <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-code UnderlineNav-octicon d-none d-sm-inline">
    <path d="m11.28 3.22 4.25 4.25a.75.75 0 0 1 0 1.06l-4.25 4.25a.749.749 0 0 1-1.275-.326.749.749 0 0 1 .215-.734L13.94 8l-3.72-3.72a.749.749 0 0 1 .326-1.275.749.749 0 0 1 .734.215Zm-6.56 0a.751.751 0 0 1 1.042.018.751.751 0 0 1 .018 1.042L2.06 8l3.72 3.72a.749.749 0 0 1-.326 1.275.749.749 0 0 1-.734-.215L.47 8.53a.75.75 0 0 1 0-1.06Z"></path>
</svg>
        <span data-content="Code">Code</span>
          <span id="code-repo-tab-count" data-pjax-replace="" data-turbo-replace="" title="Not available" data-view-component="true" class="Counter"></span>


    
</a></li>
      <li data-view-component="true" class="d-inline-flex">
  <a id="issues-tab" href="https://github.com/SpotX-CLI/SpotX-Linux/issues" data-tab-item="i1issues-tab" data-selected-links="repo_issues repo_labels repo_milestones /SpotX-CLI/SpotX-Linux/issues" data-pjax="#repo-content-pjax-container" data-turbo-frame="repo-content-turbo-frame" data-hotkey="g i" data-analytics-event="{&quot;category&quot;:&quot;Underline navbar&quot;,&quot;action&quot;:&quot;Click tab&quot;,&quot;label&quot;:&quot;Issues&quot;,&quot;target&quot;:&quot;UNDERLINE_NAV.TAB&quot;}" data-view-component="true" class="UnderlineNav-item no-wrap js-responsive-underlinenav-item js-selected-navigation-item">
    
              <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-issue-opened UnderlineNav-octicon d-none d-sm-inline">
    <path d="M8 9.5a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3Z"></path><path d="M8 0a8 8 0 1 1 0 16A8 8 0 0 1 8 0ZM1.5 8a6.5 6.5 0 1 0 13 0 6.5 6.5 0 0 0-13 0Z"></path>
</svg>
        <span data-content="Issues">Issues</span>
          <span id="issues-repo-tab-count" data-pjax-replace="" data-turbo-replace="" title="4" data-view-component="true" class="Counter">4</span>


    
</a></li>
      <li data-view-component="true" class="d-inline-flex">
  <a id="pull-requests-tab" href="https://github.com/SpotX-CLI/SpotX-Linux/pulls" data-tab-item="i2pull-requests-tab" data-selected-links="repo_pulls checks /SpotX-CLI/SpotX-Linux/pulls" data-pjax="#repo-content-pjax-container" data-turbo-frame="repo-content-turbo-frame" data-hotkey="g p" data-analytics-event="{&quot;category&quot;:&quot;Underline navbar&quot;,&quot;action&quot;:&quot;Click tab&quot;,&quot;label&quot;:&quot;Pull requests&quot;,&quot;target&quot;:&quot;UNDERLINE_NAV.TAB&quot;}" data-view-component="true" class="UnderlineNav-item no-wrap js-responsive-underlinenav-item js-selected-navigation-item">
    
              <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-git-pull-request UnderlineNav-octicon d-none d-sm-inline">
    <path d="M1.5 3.25a2.25 2.25 0 1 1 3 2.122v5.256a2.251 2.251 0 1 1-1.5 0V5.372A2.25 2.25 0 0 1 1.5 3.25Zm5.677-.177L9.573.677A.25.25 0 0 1 10 .854V2.5h1A2.5 2.5 0 0 1 13.5 5v5.628a2.251 2.251 0 1 1-1.5 0V5a1 1 0 0 0-1-1h-1v1.646a.25.25 0 0 1-.427.177L7.177 3.427a.25.25 0 0 1 0-.354ZM3.75 2.5a.75.75 0 1 0 0 1.5.75.75 0 0 0 0-1.5Zm0 9.5a.75.75 0 1 0 0 1.5.75.75 0 0 0 0-1.5Zm8.25.75a.75.75 0 1 0 1.5 0 .75.75 0 0 0-1.5 0Z"></path>
</svg>
        <span data-content="Pull requests">Pull requests</span>
          <span id="pull-requests-repo-tab-count" data-pjax-replace="" data-turbo-replace="" title="1" data-view-component="true" class="Counter">1</span>


    
</a></li>
      <li data-view-component="true" class="d-inline-flex">
  <a id="discussions-tab" href="https://github.com/SpotX-CLI/SpotX-Linux/discussions" data-tab-item="i3discussions-tab" data-selected-links="repo_discussions /SpotX-CLI/SpotX-Linux/discussions" data-pjax="#repo-content-pjax-container" data-turbo-frame="repo-content-turbo-frame" data-hotkey="g g" data-analytics-event="{&quot;category&quot;:&quot;Underline navbar&quot;,&quot;action&quot;:&quot;Click tab&quot;,&quot;label&quot;:&quot;Discussions&quot;,&quot;target&quot;:&quot;UNDERLINE_NAV.TAB&quot;}" data-view-component="true" class="UnderlineNav-item no-wrap js-responsive-underlinenav-item js-selected-navigation-item">
    
              <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-comment-discussion UnderlineNav-octicon d-none d-sm-inline">
    <path d="M1.75 1h8.5c.966 0 1.75.784 1.75 1.75v5.5A1.75 1.75 0 0 1 10.25 10H7.061l-2.574 2.573A1.458 1.458 0 0 1 2 11.543V10h-.25A1.75 1.75 0 0 1 0 8.25v-5.5C0 1.784.784 1 1.75 1ZM1.5 2.75v5.5c0 .138.112.25.25.25h1a.75.75 0 0 1 .75.75v2.19l2.72-2.72a.749.749 0 0 1 .53-.22h3.5a.25.25 0 0 0 .25-.25v-5.5a.25.25 0 0 0-.25-.25h-8.5a.25.25 0 0 0-.25.25Zm13 2a.25.25 0 0 0-.25-.25h-.5a.75.75 0 0 1 0-1.5h.5c.966 0 1.75.784 1.75 1.75v5.5A1.75 1.75 0 0 1 14.25 12H14v1.543a1.458 1.458 0 0 1-2.487 1.03L9.22 12.28a.749.749 0 0 1 .326-1.275.749.749 0 0 1 .734.215l2.22 2.22v-2.19a.75.75 0 0 1 .75-.75h1a.25.25 0 0 0 .25-.25Z"></path>
</svg>
        <span data-content="Discussions">Discussions</span>
          <span id="discussions-repo-tab-count" data-pjax-replace="" data-turbo-replace="" title="Not available" data-view-component="true" class="Counter"></span>


    
</a></li>
      <li data-view-component="true" class="d-inline-flex">
  <a id="actions-tab" href="https://github.com/SpotX-CLI/SpotX-Linux/actions" data-tab-item="i4actions-tab" data-selected-links="repo_actions /SpotX-CLI/SpotX-Linux/actions" data-pjax="#repo-content-pjax-container" data-turbo-frame="repo-content-turbo-frame" data-hotkey="g a" data-analytics-event="{&quot;category&quot;:&quot;Underline navbar&quot;,&quot;action&quot;:&quot;Click tab&quot;,&quot;label&quot;:&quot;Actions&quot;,&quot;target&quot;:&quot;UNDERLINE_NAV.TAB&quot;}" data-view-component="true" class="UnderlineNav-item no-wrap js-responsive-underlinenav-item js-selected-navigation-item">
    
              <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-play UnderlineNav-octicon d-none d-sm-inline">
    <path d="M8 0a8 8 0 1 1 0 16A8 8 0 0 1 8 0ZM1.5 8a6.5 6.5 0 1 0 13 0 6.5 6.5 0 0 0-13 0Zm4.879-2.773 4.264 2.559a.25.25 0 0 1 0 .428l-4.264 2.559A.25.25 0 0 1 6 10.559V5.442a.25.25 0 0 1 .379-.215Z"></path>
</svg>
        <span data-content="Actions">Actions</span>
          <span id="actions-repo-tab-count" data-pjax-replace="" data-turbo-replace="" title="Not available" data-view-component="true" class="Counter"></span>


    
</a></li>
      <li data-view-component="true" class="d-inline-flex">
  <a id="projects-tab" href="https://github.com/SpotX-CLI/SpotX-Linux/projects" data-tab-item="i5projects-tab" data-selected-links="repo_projects new_repo_project repo_project /SpotX-CLI/SpotX-Linux/projects" data-pjax="#repo-content-pjax-container" data-turbo-frame="repo-content-turbo-frame" data-hotkey="g b" data-analytics-event="{&quot;category&quot;:&quot;Underline navbar&quot;,&quot;action&quot;:&quot;Click tab&quot;,&quot;label&quot;:&quot;Projects&quot;,&quot;target&quot;:&quot;UNDERLINE_NAV.TAB&quot;}" data-view-component="true" class="UnderlineNav-item no-wrap js-responsive-underlinenav-item js-selected-navigation-item">
    
              <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-table UnderlineNav-octicon d-none d-sm-inline">
    <path d="M0 1.75C0 .784.784 0 1.75 0h12.5C15.216 0 16 .784 16 1.75v12.5A1.75 1.75 0 0 1 14.25 16H1.75A1.75 1.75 0 0 1 0 14.25ZM6.5 6.5v8h7.75a.25.25 0 0 0 .25-.25V6.5Zm8-1.5V1.75a.25.25 0 0 0-.25-.25H6.5V5Zm-13 1.5v7.75c0 .138.112.25.25.25H5v-8ZM5 5V1.5H1.75a.25.25 0 0 0-.25.25V5Z"></path>
</svg>
        <span data-content="Projects">Projects</span>
          <span id="projects-repo-tab-count" data-pjax-replace="" data-turbo-replace="" title="0" data-view-component="true" class="Counter" hidden="hidden">0</span>


    
</a></li>
      <li data-view-component="true" class="d-inline-flex">
  <a id="security-tab" href="https://github.com/SpotX-CLI/SpotX-Linux/security" data-tab-item="i6security-tab" data-selected-links="security overview alerts policy token_scanning code_scanning /SpotX-CLI/SpotX-Linux/security" data-pjax="#repo-content-pjax-container" data-turbo-frame="repo-content-turbo-frame" data-hotkey="g s" data-analytics-event="{&quot;category&quot;:&quot;Underline navbar&quot;,&quot;action&quot;:&quot;Click tab&quot;,&quot;label&quot;:&quot;Security&quot;,&quot;target&quot;:&quot;UNDERLINE_NAV.TAB&quot;}" data-view-component="true" class="UnderlineNav-item no-wrap js-responsive-underlinenav-item js-selected-navigation-item">
    
              <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-shield UnderlineNav-octicon d-none d-sm-inline">
    <path d="M7.467.133a1.748 1.748 0 0 1 1.066 0l5.25 1.68A1.75 1.75 0 0 1 15 3.48V7c0 1.566-.32 3.182-1.303 4.682-.983 1.498-2.585 2.813-5.032 3.855a1.697 1.697 0 0 1-1.33 0c-2.447-1.042-4.049-2.357-5.032-3.855C1.32 10.182 1 8.566 1 7V3.48a1.75 1.75 0 0 1 1.217-1.667Zm.61 1.429a.25.25 0 0 0-.153 0l-5.25 1.68a.25.25 0 0 0-.174.238V7c0 1.358.275 2.666 1.057 3.86.784 1.194 2.121 2.34 4.366 3.297a.196.196 0 0 0 .154 0c2.245-.956 3.582-2.104 4.366-3.298C13.225 9.666 13.5 8.36 13.5 7V3.48a.251.251 0 0 0-.174-.237l-5.25-1.68ZM8.75 4.75v3a.75.75 0 0 1-1.5 0v-3a.75.75 0 0 1 1.5 0ZM9 10.5a1 1 0 1 1-2 0 1 1 0 0 1 2 0Z"></path>
</svg>
        <span data-content="Security">Security</span>
          

    
</a></li>
      <li data-view-component="true" class="d-inline-flex">
  <a id="insights-tab" href="https://github.com/SpotX-CLI/SpotX-Linux/pulse" data-tab-item="i7insights-tab" data-selected-links="repo_graphs repo_contributors dependency_graph dependabot_updates pulse people community /SpotX-CLI/SpotX-Linux/pulse" data-pjax="#repo-content-pjax-container" data-turbo-frame="repo-content-turbo-frame" data-analytics-event="{&quot;category&quot;:&quot;Underline navbar&quot;,&quot;action&quot;:&quot;Click tab&quot;,&quot;label&quot;:&quot;Insights&quot;,&quot;target&quot;:&quot;UNDERLINE_NAV.TAB&quot;}" data-view-component="true" class="UnderlineNav-item no-wrap js-responsive-underlinenav-item js-selected-navigation-item">
    
              <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-graph UnderlineNav-octicon d-none d-sm-inline">
    <path d="M1.5 1.75V13.5h13.75a.75.75 0 0 1 0 1.5H.75a.75.75 0 0 1-.75-.75V1.75a.75.75 0 0 1 1.5 0Zm14.28 2.53-5.25 5.25a.75.75 0 0 1-1.06 0L7 7.06 4.28 9.78a.751.751 0 0 1-1.042-.018.751.751 0 0 1-.018-1.042l3.25-3.25a.75.75 0 0 1 1.06 0L10 7.94l4.72-4.72a.751.751 0 0 1 1.042.018.751.751 0 0 1 .018 1.042Z"></path>
</svg>
        <span data-content="Insights">Insights</span>
          <span id="insights-repo-tab-count" data-pjax-replace="" data-turbo-replace="" title="Not available" data-view-component="true" class="Counter"></span>


    
</a></li>
</ul>
    <div style="visibility:hidden;" data-view-component="true" class="UnderlineNav-actions js-responsive-underlinenav-overflow position-absolute pr-3 pr-md-4 pr-lg-5 right-0">      <details data-view-component="true" class="details-overlay details-reset position-relative">
  <summary role="button" data-view-component="true" aria-haspopup="menu">          <div class="UnderlineNav-item mr-0 border-0">
            <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-kebab-horizontal">
    <path d="M8 9a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3ZM1.5 9a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3Zm13 0a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3Z"></path>
</svg>
            <span class="sr-only">More</span>
          </div>
</summary>
  <details-menu role="menu" data-view-component="true" class="dropdown-menu dropdown-menu-sw">          <ul>
              <li data-menu-item="i0code-tab" hidden="">
                <a role="menuitem" class="js-selected-navigation-item selected dropdown-item" aria-current="page" data-selected-links="repo_source repo_downloads repo_commits repo_releases repo_tags repo_branches repo_packages repo_deployments /SpotX-CLI/SpotX-Linux" href="https://github.com/SpotX-CLI/SpotX-Linux">
                  Code
</a>              </li>
              <li data-menu-item="i1issues-tab" hidden="">
                <a role="menuitem" class="js-selected-navigation-item dropdown-item" data-selected-links="repo_issues repo_labels repo_milestones /SpotX-CLI/SpotX-Linux/issues" href="https://github.com/SpotX-CLI/SpotX-Linux/issues">
                  Issues
</a>              </li>
              <li data-menu-item="i2pull-requests-tab" hidden="">
                <a role="menuitem" class="js-selected-navigation-item dropdown-item" data-selected-links="repo_pulls checks /SpotX-CLI/SpotX-Linux/pulls" href="https://github.com/SpotX-CLI/SpotX-Linux/pulls">
                  Pull requests
</a>              </li>
              <li data-menu-item="i3discussions-tab" hidden="">
                <a role="menuitem" class="js-selected-navigation-item dropdown-item" data-selected-links="repo_discussions /SpotX-CLI/SpotX-Linux/discussions" href="https://github.com/SpotX-CLI/SpotX-Linux/discussions">
                  Discussions
</a>              </li>
              <li data-menu-item="i4actions-tab" hidden="">
                <a role="menuitem" class="js-selected-navigation-item dropdown-item" data-selected-links="repo_actions /SpotX-CLI/SpotX-Linux/actions" href="https://github.com/SpotX-CLI/SpotX-Linux/actions">
                  Actions
</a>              </li>
              <li data-menu-item="i5projects-tab" hidden="">
                <a role="menuitem" class="js-selected-navigation-item dropdown-item" data-selected-links="repo_projects new_repo_project repo_project /SpotX-CLI/SpotX-Linux/projects" href="https://github.com/SpotX-CLI/SpotX-Linux/projects">
                  Projects
</a>              </li>
              <li data-menu-item="i6security-tab" hidden="">
                <a role="menuitem" class="js-selected-navigation-item dropdown-item" data-selected-links="security overview alerts policy token_scanning code_scanning /SpotX-CLI/SpotX-Linux/security" href="https://github.com/SpotX-CLI/SpotX-Linux/security">
                  Security
</a>              </li>
              <li data-menu-item="i7insights-tab" hidden="">
                <a role="menuitem" class="js-selected-navigation-item dropdown-item" data-selected-links="repo_graphs repo_contributors dependency_graph dependabot_updates pulse people community /SpotX-CLI/SpotX-Linux/pulse" href="https://github.com/SpotX-CLI/SpotX-Linux/pulse">
                  Insights
</a>              </li>
          </ul>
</details-menu>
</details></div>
</nav>

  </div>

  



<turbo-frame id="repo-content-turbo-frame" target="_top" data-turbo-action="advance" class="">
    <div id="repo-content-pjax-container" class="repository-content ">
      <a href="https://github.dev/" class="d-none js-github-dev-shortcut" data-hotkey=".">Open in github.dev</a>
  <a href="https://github.dev/" class="d-none js-github-dev-new-tab-shortcut" data-hotkey="Shift+.,Shift+&gt;,&gt;" target="_blank">Open in a new github.dev tab</a>
    <a class="d-none" data-hotkey="," target="_blank" href="https://github.com/codespaces/new/SpotX-CLI/SpotX-Linux/tree/main?resume=1">Open in codespace</a>



    
      
    





<react-app app-name="react-code-view" initial-path="/SpotX-CLI/SpotX-Linux/blob/main/install.sh" style="min-height: calc(100vh - 62px)" data-ssr="false" data-lazy="false" data-alternate="false" data-catalyst="" class="loaded">
  
  <script type="application/json" data-target="react-app.embeddedData">{"payload":{"allShortcutsEnabled":true,"fileTree":{"":{"items":[{"name":".github","path":".github","contentType":"directory"},{"name":"LICENSE","path":"LICENSE","contentType":"file"},{"name":"install.sh","path":"install.sh","contentType":"file"},{"name":"readme.md","path":"readme.md","contentType":"file"},{"name":"uninstall.sh","path":"uninstall.sh","contentType":"file"}],"totalCount":5}},"fileTreeProcessingTime":2.935162,"foldersToFetch":[],"reducedMotionEnabled":"system","repo":{"id":555066047,"defaultBranch":"main","name":"SpotX-Linux","ownerLogin":"SpotX-CLI","currentUserCanPush":false,"isFork":false,"isEmpty":false,"createdAt":"2022-10-20T23:24:09.000+01:00","ownerAvatar":"https://avatars.githubusercontent.com/u/114853984?v=4","public":true,"private":false},"refInfo":{"name":"main","listCacheKey":"v0:1674237441.85801","canEdit":true,"refType":"branch","currentOid":"fa4e804c8ec813e57e0570307a1f91837b8fc4f6"},"path":"install.sh","currentUser":{"id":100360644,"login":"anfreire","userEmail":"anfreire.dev@gmail.com"},"blob":{"rawBlob":"#!/usr/bin/env bash\n\nSPOTX_VERSION=\"1.2.3.1115-1\"\n\n# Dependencies check\ncommand -v perl \u003e/dev/null || { echo -e \"\\nperl was not found, please install. Exiting...\\n\" \u003e\u00262; exit 1; }\ncommand -v unzip \u003e/dev/null || { echo -e \"\\nunzip was not found, please install. Exiting...\\n\" \u003e\u00262; exit 1; }\ncommand -v zip \u003e/dev/null || { echo -e \"\\nzip was not found, please install. Exiting...\\n\" \u003e\u00262; exit 1; }\n\n# Script flags\nCACHE_FLAG='false'\nEXPERIMENTAL_FLAG='false'\nFORCE_FLAG='false'\nPATH_FLAG=''\nPREMIUM_FLAG='false'\n\nwhile getopts 'cefhopP:' flag; do\n  case \"${flag}\" in\n    c) CACHE_FLAG='true' ;;\n    E) EXCLUDE_FLAG+=(\"${OPTARG}\") ;; #currently disabled\n    e) EXPERIMENTAL_FLAG='true' ;;\n    f) FORCE_FLAG='true' ;;\n    h) HIDE_PODCASTS_FLAG='true' ;;\n    o) OLD_UI_FLAG='true' ;;\n    P) \n      PATH_FLAG=\"${OPTARG}\"\n      INSTALL_PATH=\"${PATH_FLAG}\" ;;\n    p) PREMIUM_FLAG='true' ;;\n    *) \n      echo \"Error: Flag not supported.\"\n      exit ;;\n  esac\ndone\n\n# Handle exclude flag(s)\nfor EXCLUDE_VAL in \"${EXCLUDE_FLAG[@]}\"; do\n  if [[ \"${EXCLUDE_VAL}\" == \"leftsidebar\" ]]; then EX_LEFTSIDEBAR='true'; fi\ndone\n\n# Perl command\nPERL=\"perl -pi -w -e\"\n\n# Ad-related regex\nAD_EMPTY_AD_BLOCK='s|adsEnabled:!0|adsEnabled:!1|'\nAD_PLAYLIST_SPONSORS='s|allSponsorships||'\nAD_UPGRADE_BUTTON='s/(return|.=.=\u003e)\"free\"===(.+?)(return|.=.=\u003e)\"premium\"===/$1\"premium\"===$2$3\"free\"===/g'\nAD_AUDIO_ADS='s/(case .:|async enable\\(.\\)\\{)(this.enabled=.+?\\(.{1,3},\"audio\"\\),|return this.enabled=...+?\\(.{1,3},\"audio\"\\))((;case 4:)?this.subscription=this.audioApi).+?this.onAdMessage\\)/$1$3.cosmosConnector.increaseStreamTime(-100000000000)/'\nAD_BILLBOARD='s|.(\\?\\[.{1,6}[a-zA-Z].leaderboard,)|false$1|'\nAD_UPSELL='s|(Enables quicksilver in-app messaging modal\",default:)(!0)|$1false|'\n\n# Experimental (A/B test) features\nENABLE_ADD_PLAYLIST='s|(Enable support for adding a playlist to another playlist\",default:)(!1)|$1true|s'\nENABLE_BAD_BUNNY='s|(Enable a different heart button for Bad Bunny\",default:)(!1)|$1true|s'\nENABLE_BALLOONS='s|(Enable showing balloons on album release date anniversaries\",default:)(!1)|$1true|s'\nENABLE_BLOCK_USERS='s|(Enable block users feature in clientX\",default:)(!1)|$1true|s'\nENABLE_CAROUSELS='s|(Use carousels on Home\",default:)(!1)|$1true|s'\nENABLE_CLEAR_DOWNLOADS='s|(Enable option in settings to clear all downloads\",default:)(!1)|$1true|s'\nENABLE_DEVICE_LIST_LOCAL='s|(Enable splitting the device list based on local network\",default:)(!1)|$1true|s'\nENABLE_DISCOG_SHELF='s|(Enable a condensed disography shelf on artist pages\",default:)(!1)|$1true|s'\nENABLE_ENHANCE_PLAYLIST='s|(Enable Enhance Playlist UI and functionality for end-users\",default:)(!1)|$1true|s'\nENABLE_ENHANCE_SONGS='s|(Enable Enhance Liked Songs UI and functionality\",default:)(!1)|$1true|s'\nENABLE_EQUALIZER='s|(Enable audio equalizer for Desktop and Web Player\",default:)(!1)|$1true|s'\nENABLE_FOLLOWERS_ON_PROFILE='s|(Enable a setting to control if followers and following lists are shown on profile\",default:)(!1)|$1true|s'\nENABLE_FORGET_DEVICES='s|(Enable the option to Forget Devices\",default:)(!1)|$1true|s'\nENABLE_IGNORE_REC='s|(Enable Ignore In Recommendations for desktop and web\",default:)(!1)|$1true|s'\nENABLE_LIKED_SONGS='s|(Enable Liked Songs section on Artist page\",default:)(!1)|$1true|s'\nENABLE_LYRICS_CHECK='s|(With this enabled, clients will check whether tracks have lyrics available\",default:)(!1)|$1true|s'\nENABLE_LYRICS_MATCH='s|(Enable Lyrics match labels in search results\",default:)(!1)|$1true|s'\nENABLE_PATHFINDER_DATA='s|(Fetch Browse data from Pathfinder\",default:)(!1)|$1true|s'\nENABLE_PLAYLIST_CREATION_FLOW='s|(Enables new playlist creation flow in Web Player and DesktopX\",default:)(!1)|$1true|s'\nENABLE_PLAYLIST_PERMISSIONS_FLOWS='s|(Enable Playlist Permissions flows for Prod\",default:)(!1)|$1true|s'\nENABLE_PODCAST_PLAYBACK_SPEED='s|(playback speed range from 0.5-3.5 with every 0.1 increment\",default:)(!1)|$1true|s'\nENABLE_PODCAST_TRIMMING='s|(Enable silence trimming in podcasts\",default:)(!1)|$1true|s'\nENABLE_SEARCH_BOX='s|(Adds a search box so users are able to filter playlists when trying to add songs to a playlist using the contextmenu\",default:)(!1)|$1true|s'\nENABLE_SIMILAR_PLAYLIST='s/,(.\\.isOwnedBySelf\u0026\u0026)((\\(.{0,11}\\)|..createElement)\\(.{1,3}Fragment,.+?{(uri:.|spec:.),(uri:.|spec:.).+?contextmenu.create-similar-playlist\"\\)}\\),)/,$2$1/s'\n\n# Home screen UI (new)\nNEW_UI='s|(Enable the new home structure and navigation\",values:.,default:)(..DISABLED)|$1true|'\nNEW_UI_2='s|(Enable the new home structure and navigation\",values:.,default:.)(.DISABLED)|$1.ENABLED_CENTER|'\nAUDIOBOOKS_CLIENTX='s|(Enable Audiobooks feature on ClientX\",default:)(!1)|$1true|s'\nENABLE_LEFT_SIDEBAR='s|(Enable Your Library X view of the left sidebar\",default:)(!1)|$1true|s'\nENABLE_RIGHT_SIDEBAR='s|(Enable the view on the right sidebar\",default:)(!1)|$1true|s'\nENABLE_RIGHT_SIDEBAR_LYRICS='s|(Show lyrics in the right sidebar\",default:)(!1)|$1true|s'\n\n# Hide Premium-only features\nHIDE_DL_QUALITY='s/(\\(.,..jsxs\\)\\(.{1,3}|(.\\(\\).|..)createElement\\(.{1,4}),\\{(filterMatchQuery|filter:.,title|(variant:\"viola\",semanticColor:\"textSubdued\"|..:\"span\",variant:.{3,6}mesto,color:.{3,6}),htmlFor:\"desktop.settings.downloadQuality.+?).{1,6}get\\(\"desktop.settings.downloadQuality.title.+?(children:.{1,2}\\(.,.\\).+?,|\\(.,.\\){3,4},|,.\\)}},.\\(.,.\\)\\),)//'\nHIDE_DL_ICON=' .BKsbV2Xl786X9a09XROH {display:none}'\nHIDE_DL_MENU=' button.wC9sIed7pfp47wZbmU6m.pzkhLqffqF_4hucrVVQA {display:none}'\nHIDE_VERY_HIGH=' #desktop\\.settings\\.streamingQuality\u003eoption:nth-child(5) {display:none}'\n\n# Hide Podcasts/Episodes/Audiobooks on home screen\nHIDE_PODCASTS='s|withQueryParameters\\(.\\)\\{return this.queryParameters=.,this}|withQueryParameters(e){return this.queryParameters=(e.types?{...e, types: e.types.split(\",\").filter(_ =\u003e ![\"episode\",\"show\"].includes(_)).join(\",\")}:e),this}|'\nHIDE_PODCASTS2='s/(!Array.isArray\\(.\\)\\|\\|.===..length)/$1||e.children[0].key.includes('\\''episode'\\'')||e.children[0].key.includes('\\''show'\\'')/'\nHIDE_PODCASTS3='s/(!Array.isArray\\(.\\)\\|\\|.===..length)/$1||e[0].key.includes('\\''episode'\\'')||e[0].key.includes('\\''show'\\'')/'\n\n# Log-related regex\nLOG_1='s|sp://logging/v3/\\w+||g'\nLOG_SENTRY='s|this\\.getStackTop\\(\\)\\.client=e|return;$\u0026|'\n\n# Spotify Connect unlock / UI\nCONNECT_OLD_1='s| connect-device-list-item--disabled||' # 1.1.70.610+\nCONNECT_OLD_2='s|connect-picker.unavailable-to-control|spotify-connect|' # 1.1.70.610+\nCONNECT_OLD_3='s|(className:.,disabled:)(..)|$1false|' # 1.1.70.610+\nCONNECT_NEW='s/return (..isDisabled)(\\?(..createElement|\\(.{1,10}\\))\\(..,)/return false$2/' # 1.1.91.824+\nDEVICE_PICKER_NEW='s|(Enable showing a new and improved device picker UI\",default:)(!1)|$1true|' # 1.1.90.855 - 1.1.95.893\nDEVICE_PICKER_OLD='s|(Enable showing a new and improved device picker UI\",default:)(!0)|$1false|' # 1.1.96.783 - 1.1.97.962\n\n# Credits\necho\necho \"**************************\"\necho \"SpotX-Linux by @SpotX-CLI\"\necho \"**************************\"\necho\n\n# Report SpotX version\necho -e \"SpotX-Linux version: ${SPOTX_VERSION}\\n\"\n\n# Locate install directory\nif [ -z ${INSTALL_PATH+x} ]; then\n  INSTALL_PATH=$(readlink -e `type -p spotify` 2\u003e/dev/null | rev | cut -d/ -f2- | rev)\n  if [[ -d \"${INSTALL_PATH}\" \u0026\u0026 \"${INSTALL_PATH}\" != \"/usr/bin\" ]]; then\n    echo \"Spotify directory found in PATH: ${INSTALL_PATH}\"\n  elif [[ ! -d \"${INSTALL_PATH}\" ]]; then\n    echo -e \"\\nSpotify not found in PATH. Searching for Spotify directory...\"\n    INSTALL_PATH=$(timeout 10 find / -type f -path \"*/spotify*Apps/*\" -name \"xpui.spa\" -size -7M -size +3M -print -quit 2\u003e/dev/null | rev | cut -d/ -f3- | rev)\n    if [[ -d \"${INSTALL_PATH}\" ]]; then\n      echo \"Spotify directory found: ${INSTALL_PATH}\"\n    elif [[ ! -d \"${INSTALL_PATH}\" ]]; then\n      echo -e \"Spotify directory not found. Set directory path with -P flag.\\nExiting...\\n\"\n      exit; fi\n  elif [[ \"${INSTALL_PATH}\" == \"/usr/bin\" ]]; then\n    echo -e \"\\nSpotify PATH is set to /usr/bin, searching for Spotify directory...\"\n    INSTALL_PATH=$(timeout 10 find / -type f -path \"*/spotify*Apps/*\" -name \"xpui.spa\" -size -7M -size +3M -print -quit 2\u003e/dev/null | rev | cut -d/ -f3- | rev)\n    if [[ -d \"${INSTALL_PATH}\" \u0026\u0026 \"${INSTALL_PATH}\" != \"/usr/bin\" ]]; then\n      echo \"Spotify directory found: ${INSTALL_PATH}\"\n    elif [[ \"${INSTALL_PATH}\" == \"/usr/bin\" ]] || [[ ! -d \"${INSTALL_PATH}\" ]]; then\n      echo -e \"Spotify directory not found. Set directory path with -P flag.\\nExiting...\\n\"\n      exit; fi; fi\nelse\n  if [[ ! -d \"${INSTALL_PATH}\" ]]; then\n    echo -e \"Directory path set by -P was not found.\\nExiting...\\n\"\n    exit\n  elif [[ ! -f \"${INSTALL_PATH}/Apps/xpui.spa\" ]]; then\n    echo -e \"No xpui found in directory provided with -P.\\nPlease confirm directory and try again or re-install Spotify.\\nExiting...\\n\"\n    exit; fi; fi\n\n# Find client version\nCLIENT_VERSION=$(\"${INSTALL_PATH}\"/spotify --version | cut -dn -f2- | rev | cut -d. -f2- | rev)\n\n# Version function for version comparison\nfunction ver { echo \"$@\" | awk -F. '{ printf(\"%d%03d%03d%03d\\n\", $1,$2,$3,$4); }'; }\n\n# Report Spotify version\necho -e \"\\nSpotify version: ${CLIENT_VERSION}\\n\"\n     \n# Path vars\nCACHE_PATH=\"${HOME}/.cache/spotify/\"\nXPUI_PATH=\"${INSTALL_PATH}/Apps\"\nXPUI_DIR=\"${XPUI_PATH}/xpui\"\nXPUI_BAK=\"${XPUI_PATH}/xpui.bak\"\nXPUI_SPA=\"${XPUI_PATH}/xpui.spa\"\nXPUI_JS=\"${XPUI_DIR}/xpui.js\"\nXPUI_CSS=\"${XPUI_DIR}/xpui.css\"\nHOME_V2_JS=\"${XPUI_DIR}/home-v2.js\"\nVENDOR_XPUI_JS=\"${XPUI_DIR}/vendor~xpui.js\"\n\n# xpui detection\nif [[ ! -f \"${XPUI_SPA}\" ]]; then\n  echo -e \"\\nxpui not found!\\nReinstall Spotify then try again.\\nExiting...\\n\"\n  exit\nelse\n  if [[ ! -w \"${XPUI_PATH}\" ]]; then\n    echo -e \"\\nSpotX does not have write permission in Spotify directory.\\nRequesting sudo permission...\\n\"\n    sudo chmod a+wr \"${INSTALL_PATH}\" \u0026\u0026 sudo chmod a+wr -R \"${XPUI_PATH}\"; fi\n  if [[ \"${FORCE_FLAG}\" == \"false\" ]]; then\n    if [[ -f \"${XPUI_BAK}\" ]]; then\n      echo \"SpotX backup found, SpotX has already been used on this install.\"\n      echo -e \"Re-run SpotX using the '-f' flag to force xpui patching.\\n\"\n      echo \"Skipping xpui patches and continuing SpotX...\"\n      XPUI_SKIP=\"true\"\n    else\n      echo \"Creating xpui backup...\"\n      cp \"${XPUI_SPA}\" \"${XPUI_BAK}\"\n      XPUI_SKIP=\"false\"; fi\n  else\n    if [[ -f \"${XPUI_BAK}\" ]]; then\n      echo \"Backup xpui found, restoring original...\"\n      rm \"${XPUI_SPA}\"\n      cp \"${XPUI_BAK}\" \"${XPUI_SPA}\"\n      XPUI_SKIP=\"false\"\n    else\n      echo \"Creating xpui backup...\"\n      cp \"${XPUI_SPA}\" \"${XPUI_BAK}\"\n      XPUI_SKIP=\"false\"; fi; fi; fi\n\n# Extract xpui.spa\nif [[ \"${XPUI_SKIP}\" == \"false\" ]]; then\n  echo \"Extracting xpui...\"\n  unzip -qq \"${XPUI_SPA}\" -d \"${XPUI_DIR}\"\n  if grep -Fq \"SpotX\" \"${XPUI_JS}\"; then\n    echo -e \"\\nWarning: Detected SpotX patches but no backup file!\"\n    echo -e \"Further xpui patching not allowed until Spotify is reinstalled/upgraded.\\n\"\n    echo \"Skipping xpui patches and continuing SpotX...\"\n    XPUI_SKIP=\"true\"\n    rm \"${XPUI_BAK}\" 2\u003e/dev/null\n    rm -rf \"${XPUI_DIR}\" 2\u003e/dev/null\n  else\n    rm \"${XPUI_SPA}\"; fi; fi\n\necho \"Applying SpotX patches...\"\n\nif [[ \"${XPUI_SKIP}\" == \"false\" ]]; then\n  if [[ \"${PREMIUM_FLAG}\" == \"false\" ]]; then\n    # Remove Empty ad block\n    echo \"Removing ad-related content...\"\n    $PERL \"${AD_EMPTY_AD_BLOCK}\" \"${XPUI_JS}\"\n    # Remove Playlist sponsors\n    $PERL \"${AD_PLAYLIST_SPONSORS}\" \"${XPUI_JS}\"\n    # Remove Upgrade button\n    $PERL \"${AD_UPGRADE_BUTTON}\" \"${XPUI_JS}\"\n    # Remove Audio ads\n    $PERL \"${AD_AUDIO_ADS}\" \"${XPUI_JS}\"\n    # Remove billboard ads\n    $PERL \"${AD_BILLBOARD}\" \"${XPUI_JS}\"\n    # Remove premium upsells\n    $PERL \"${AD_UPSELL}\" \"${XPUI_JS}\"\n    \n    # Remove Premium-only features\n    echo \"Removing premium-only features...\"\n    $PERL \"${HIDE_DL_QUALITY}\" \"${XPUI_JS}\"\n    echo \"${HIDE_DL_ICON}\" \u003e\u003e \"${XPUI_CSS}\"\n    echo \"${HIDE_DL_MENU}\" \u003e\u003e \"${XPUI_CSS}\"\n    echo \"${HIDE_VERY_HIGH}\" \u003e\u003e \"${XPUI_CSS}\"\n    \n    # Unlock Spotify Connect\n    echo \"Unlocking Spotify Connect...\"\n    if [[ $(ver \"${CLIENT_VERSION}\") -ge $(ver \"1.1.70.610\") \u0026\u0026 $(ver \"${CLIENT_VERSION}\") -lt $(ver \"1.1.91.824\") ]]; then\n      $PERL \"${CONNECT_OLD_1}\" \"${XPUI_JS}\"\n      $PERL \"${CONNECT_OLD_2}\" \"${XPUI_JS}\"\n      $PERL \"${CONNECT_OLD_3}\" \"${XPUI_JS}\"\n    elif [[ $(ver \"${CLIENT_VERSION}\") -ge $(ver \"1.1.91.824\") \u0026\u0026 $(ver \"${CLIENT_VERSION}\") -lt $(ver \"1.1.96.783\") ]]; then\n      $PERL \"${DEVICE_PICKER_NEW}\" \"${XPUI_JS}\"\n      $PERL \"${CONNECT_NEW}\" \"${XPUI_JS}\"\n    elif [[ $(ver \"${CLIENT_VERSION}\") -gt $(ver \"1.1.96.783\") ]]; then\n      $PERL \"${CONNECT_NEW}\" \"${XPUI_JS}\"; fi\n  else\n    echo \"Premium subscription setup selected...\"; fi; fi\n\n# Experimental patches\nif [[ \"${XPUI_SKIP}\" == \"false\" ]]; then\n  if [[ \"${EXPERIMENTAL_FLAG}\" == \"true\" ]]; then\n    echo \"Adding experimental features...\"\n    if [[ $(ver \"${CLIENT_VERSION}\") -ge $(ver \"1.1.99.871\") ]]; then $PERL \"${ENABLE_ADD_PLAYLIST}\" \"${XPUI_JS}\"; fi\n    if [[ $(ver \"${CLIENT_VERSION}\") -ge $(ver \"1.1.99.871\") ]]; then $PERL \"${ENABLE_BAD_BUNNY}\" \"${XPUI_JS}\"; fi\n    if [[ $(ver \"${CLIENT_VERSION}\") -ge $(ver \"1.1.89.854\") ]]; then $PERL \"${ENABLE_BALLOONS}\" \"${XPUI_JS}\"; fi\n    if [[ $(ver \"${CLIENT_VERSION}\") -ge $(ver \"1.1.70.610\") ]]; then $PERL \"${ENABLE_BLOCK_USERS}\" \"${XPUI_JS}\"; fi\n    if [[ $(ver \"${CLIENT_VERSION}\") -ge $(ver \"1.1.93.896\") ]]; then $PERL \"${ENABLE_CAROUSELS}\" \"${XPUI_JS}\"; fi\n    if [[ $(ver \"${CLIENT_VERSION}\") -ge $(ver \"1.1.92.644\") \u0026\u0026 $(ver \"${CLIENT_VERSION}\") -lt $(ver \"1.1.99.871\") ]]; then $PERL \"${ENABLE_CLEAR_DOWNLOADS}\" \"${XPUI_JS}\"; fi\n    if [[ $(ver \"${CLIENT_VERSION}\") -ge $(ver \"1.1.99.871\") ]]; then $PERL \"${ENABLE_DEVICE_LIST_LOCAL}\" \"${XPUI_JS}\"; fi\n    if [[ $(ver \"${CLIENT_VERSION}\") -ge $(ver \"1.1.79.763\") ]]; then $PERL \"${ENABLE_DISCOG_SHELF}\" \"${XPUI_JS}\"; fi\n    if [[ $(ver \"${CLIENT_VERSION}\") -ge $(ver \"1.1.84.716\") ]]; then $PERL \"${ENABLE_ENHANCE_PLAYLIST}\" \"${XPUI_JS}\"; fi\n    if [[ $(ver \"${CLIENT_VERSION}\") -ge $(ver \"1.1.86.857\") ]]; then $PERL \"${ENABLE_ENHANCE_SONGS}\" \"${XPUI_JS}\"; fi\n    if [[ $(ver \"${CLIENT_VERSION}\") -ge $(ver \"1.1.88.595\") ]]; then $PERL \"${ENABLE_EQUALIZER}\" \"${XPUI_JS}\"; fi\n    if [[ $(ver \"${CLIENT_VERSION}\") -ge $(ver \"1.2.1.958\") ]]; then $PERL \"${ENABLE_FOLLOWERS_ON_PROFILE}\" \"${XPUI_JS}\"; fi\n    if [[ $(ver \"${CLIENT_VERSION}\") -ge $(ver \"1.2.0.1155\") ]]; then $PERL \"${ENABLE_FORGET_DEVICES}\" \"${XPUI_JS}\"; fi\n    if [[ $(ver \"${CLIENT_VERSION}\") -ge $(ver \"1.1.87.612\") ]]; then $PERL \"${ENABLE_IGNORE_REC}\" \"${XPUI_JS}\"; fi\n    if [[ $(ver \"${CLIENT_VERSION}\") -ge $(ver \"1.1.70.610\") ]]; then $PERL \"${ENABLE_LIKED_SONGS}\" \"${XPUI_JS}\"; fi\n    if [[ $(ver \"${CLIENT_VERSION}\") -ge $(ver \"1.1.70.610\") \u0026\u0026 $(ver \"${CLIENT_VERSION}\") -lt $(ver \"1.1.94.864\") ]]; then $PERL \"${ENABLE_LYRICS_CHECK}\" \"${XPUI_JS}\"; fi\n    if [[ $(ver \"${CLIENT_VERSION}\") -ge $(ver \"1.1.87.612\") ]]; then $PERL \"${ENABLE_LYRICS_MATCH}\" \"${XPUI_JS}\"; fi\n    if [[ $(ver \"${CLIENT_VERSION}\") -ge $(ver \"1.1.70.610\") \u0026\u0026 $(ver \"${CLIENT_VERSION}\") -lt $(ver \"1.1.96.783\") ]]; then $PERL \"${ENABLE_MADE_FOR_YOU}\" \"${XPUI_JS}\"; fi\n    if [[ $(ver \"${CLIENT_VERSION}\") -ge $(ver \"1.1.91.824\") ]]; then $PERL \"${ENABLE_PATHFINDER_DATA}\" \"${XPUI_JS}\"; fi\n    if [[ $(ver \"${CLIENT_VERSION}\") -ge $(ver \"1.1.70.610\") \u0026\u0026 $(ver \"${CLIENT_VERSION}\") -lt $(ver \"1.1.94.864\") ]]; then $PERL \"${ENABLE_PLAYLIST_CREATION_FLOW}\" \"${XPUI_JS}\"; fi\n    if [[ $(ver \"${CLIENT_VERSION}\") -ge $(ver \"1.1.75.572\") ]]; then $PERL \"${ENABLE_PLAYLIST_PERMISSIONS_FLOWS}\" \"${XPUI_JS}\"; fi\n    if [[ $(ver \"${CLIENT_VERSION}\") -ge $(ver \"1.2.0.1165\") ]]; then $PERL \"${ENABLE_PODCAST_PLAYBACK_SPEED}\" \"${XPUI_JS}\"; fi\n    if [[ $(ver \"${CLIENT_VERSION}\") -ge $(ver \"1.1.99.871\") ]]; then $PERL \"${ENABLE_PODCAST_TRIMMING}\" \"${XPUI_JS}\"; fi\n    if [[ $(ver \"${CLIENT_VERSION}\") -ge $(ver \"1.1.86.857\") \u0026\u0026 $(ver \"${CLIENT_VERSION}\") -lt $(ver \"1.1.94.864\") ]]; then $PERL \"${ENABLE_SEARCH_BOX}\" \"${XPUI_JS}\"; fi\n    if [[ $(ver \"${CLIENT_VERSION}\") -ge $(ver \"1.1.85.884\") ]]; then $PERL \"${ENABLE_SIMILAR_PLAYLIST}\" \"${XPUI_JS}\"; fi; fi; fi\n\n# Remove logging\nif [[ \"${XPUI_SKIP}\" == \"false\" ]]; then\n  echo \"Removing logging...\"\n  $PERL \"${LOG_1}\" \"${XPUI_JS}\"\n  $PERL \"${LOG_SENTRY}\" \"${VENDOR_XPUI_JS}\"; fi\n\n# Handle new home screen UI\nif [[ \"${XPUI_SKIP}\" == \"false\" ]]; then\n  if [[ \"${OLD_UI_FLAG}\" == \"true\" ]]; then\n    echo \"Skipping new home UI patch...\"\n  elif [[ $(ver \"${CLIENT_VERSION}\") -gt $(ver \"1.1.93.896\") \u0026\u0026 $(ver \"${CLIENT_VERSION}\") -lt $(ver \"1.1.97.956\") ]]; then\n    echo \"Enabling new home screen UI...\"\n    $PERL \"${NEW_UI}\" \"${XPUI_JS}\"\n    $PERL \"${AUDIOBOOKS_CLIENTX}\" \"${XPUI_JS}\"\n  elif [[ $(ver \"${CLIENT_VERSION}\") -ge $(ver \"1.1.97.956\") \u0026\u0026 $(ver \"${CLIENT_VERSION}\") -lt $(ver \"1.2.3.1107\") ]]; then\n    echo \"Enabling new home screen UI...\"\n    $PERL \"${NEW_UI_2}\" \"${XPUI_JS}\"\n    $PERL \"${AUDIOBOOKS_CLIENTX}\" \"${XPUI_JS}\"\n    if [[ $(ver \"${CLIENT_VERSION}\") -ge $(ver \"1.1.98.683\") ]]; then $PERL \"${ENABLE_RIGHT_SIDEBAR}\" \"${XPUI_JS}\"; fi\n    if [[ $(ver \"${CLIENT_VERSION}\") -ge $(ver \"1.2.0.1165\") ]]; then $PERL \"${ENABLE_RIGHT_SIDEBAR_LYRICS}\" \"${XPUI_JS}\"; fi\n  elif [[ $(ver \"${CLIENT_VERSION}\") -ge $(ver \"1.2.3.1107\") ]]; then\n    echo \"Enabling new home screen UI...\"\n    $PERL \"${AUDIOBOOKS_CLIENTX}\" \"${XPUI_JS}\"\n    if [[ $(ver \"${CLIENT_VERSION}\") -ge $(ver \"1.1.97.962\") ]]; then $PERL \"${ENABLE_LEFT_SIDEBAR}\" \"${XPUI_JS}\"; fi\n    if [[ $(ver \"${CLIENT_VERSION}\") -ge $(ver \"1.1.98.683\") ]]; then $PERL \"${ENABLE_RIGHT_SIDEBAR}\" \"${XPUI_JS}\"; fi\n    if [[ $(ver \"${CLIENT_VERSION}\") -ge $(ver \"1.2.0.1165\") ]]; then $PERL \"${ENABLE_RIGHT_SIDEBAR_LYRICS}\" \"${XPUI_JS}\"; fi\n  else\n    :; fi; fi\n\n# Hide podcasts, episodes and audiobooks on home screen\nif [[ \"${XPUI_SKIP}\" == \"false\" ]]; then\n  if [[ \"${HIDE_PODCASTS_FLAG}\" == \"true\" ]]; then\n    if [[ $(ver \"${CLIENT_VERSION}\") -lt $(ver \"1.1.93.896\") ]]; then\n      echo \"Hiding non-music items on home screen...\"\n      $PERL \"${HIDE_PODCASTS}\" \"${XPUI_JS}\"\n    elif [[ $(ver \"${CLIENT_VERSION}\") -ge $(ver \"1.1.93.896\") \u0026\u0026 $(ver \"${CLIENT_VERSION}\") -le $(ver \"1.1.96.785\") ]]; then\n      echo \"Hiding non-music items on home screen...\"\n      $PERL \"${HIDE_PODCASTS2}\" \"${HOME_V2_JS}\"\n    elif [[ $(ver \"${CLIENT_VERSION}\") -gt $(ver \"1.1.96.785\") \u0026\u0026 $(ver \"${CLIENT_VERSION}\") -lt $(ver \"1.1.98.683\") ]]; then\n      echo \"Hiding non-music items on home screen...\"\n      $PERL \"${HIDE_PODCASTS3}\" \"${HOME_V2_JS}\"\n    elif [[ $(ver \"${CLIENT_VERSION}\") -ge $(ver \"1.1.98.683\") ]]; then\n      echo \"Hiding non-music items on home screen...\"\n      $PERL \"${HIDE_PODCASTS3}\" \"${XPUI_JS}\"; fi; fi; fi\n\n# Delete app cache\nif [[ \"${CACHE_FLAG}\" == \"true\" ]]; then\n  echo \"Clearing app cache...\"\n  rm -rf \"$CACHE_PATH\"; fi\n  \n# Rebuild xpui.spa\nif [[ \"${XPUI_SKIP}\" == \"false\" ]]; then\n  echo \"Rebuilding xpui...\"\n  echo -e \"\\n//# SpotX was here\" \u003e\u003e \"${XPUI_JS}\"; fi\n\n# Zip files inside xpui folder\nif [[ \"${XPUI_SKIP}\" == \"false\" ]]; then\n  (cd \"${XPUI_DIR}\"; zip -qq -r ../xpui.spa .)\n  rm -rf \"${XPUI_DIR}\"; fi\n\necho -e \"SpotX finished patching!\\n\"\n","colorizedLines":null,"stylingDirectives":[[{"start":0,"end":19,"cssClass":"pl-c"},{"start":0,"end":2,"cssClass":"pl-c"}],[],[{"start":14,"end":28,"cssClass":"pl-s"},{"start":14,"end":15,"cssClass":"pl-pds"},{"start":27,"end":28,"cssClass":"pl-pds"}],[],[{"start":0,"end":20,"cssClass":"pl-c"},{"start":0,"end":1,"cssClass":"pl-c"}],[{"start":0,"end":7,"cssClass":"pl-c1"},{"start":16,"end":17,"cssClass":"pl-k"},{"start":27,"end":29,"cssClass":"pl-k"},{"start":32,"end":36,"cssClass":"pl-c1"},{"start":40,"end":92,"cssClass":"pl-s"},{"start":40,"end":41,"cssClass":"pl-pds"},{"start":91,"end":92,"cssClass":"pl-pds"},{"start":93,"end":96,"cssClass":"pl-k"},{"start":96,"end":97,"cssClass":"pl-k"},{"start":98,"end":102,"cssClass":"pl-c1"},{"start":104,"end":105,"cssClass":"pl-k"}],[{"start":0,"end":7,"cssClass":"pl-c1"},{"start":17,"end":18,"cssClass":"pl-k"},{"start":28,"end":30,"cssClass":"pl-k"},{"start":33,"end":37,"cssClass":"pl-c1"},{"start":41,"end":94,"cssClass":"pl-s"},{"start":41,"end":42,"cssClass":"pl-pds"},{"start":93,"end":94,"cssClass":"pl-pds"},{"start":95,"end":98,"cssClass":"pl-k"},{"start":98,"end":99,"cssClass":"pl-k"},{"start":100,"end":104,"cssClass":"pl-c1"},{"start":106,"end":107,"cssClass":"pl-k"}],[{"start":0,"end":7,"cssClass":"pl-c1"},{"start":15,"end":16,"cssClass":"pl-k"},{"start":26,"end":28,"cssClass":"pl-k"},{"start":31,"end":35,"cssClass":"pl-c1"},{"start":39,"end":90,"cssClass":"pl-s"},{"start":39,"end":40,"cssClass":"pl-pds"},{"start":89,"end":90,"cssClass":"pl-pds"},{"start":91,"end":94,"cssClass":"pl-k"},{"start":94,"end":95,"cssClass":"pl-k"},{"start":96,"end":100,"cssClass":"pl-c1"},{"start":102,"end":103,"cssClass":"pl-k"}],[],[{"start":0,"end":14,"cssClass":"pl-c"},{"start":0,"end":1,"cssClass":"pl-c"}],[{"start":11,"end":18,"cssClass":"pl-s"},{"start":11,"end":12,"cssClass":"pl-pds"},{"start":17,"end":18,"cssClass":"pl-pds"}],[{"start":18,"end":25,"cssClass":"pl-s"},{"start":18,"end":19,"cssClass":"pl-pds"},{"start":24,"end":25,"cssClass":"pl-pds"}],[{"start":11,"end":18,"cssClass":"pl-s"},{"start":11,"end":12,"cssClass":"pl-pds"},{"start":17,"end":18,"cssClass":"pl-pds"}],[{"start":10,"end":12,"cssClass":"pl-s"},{"start":10,"end":11,"cssClass":"pl-pds"},{"start":11,"end":12,"cssClass":"pl-pds"}],[{"start":13,"end":20,"cssClass":"pl-s"},{"start":13,"end":14,"cssClass":"pl-pds"},{"start":19,"end":20,"cssClass":"pl-pds"}],[],[{"start":0,"end":5,"cssClass":"pl-k"},{"start":6,"end":13,"cssClass":"pl-c1"},{"start":14,"end":24,"cssClass":"pl-s"},{"start":14,"end":15,"cssClass":"pl-pds"},{"start":23,"end":24,"cssClass":"pl-pds"},{"start":29,"end":30,"cssClass":"pl-k"},{"start":31,"end":33,"cssClass":"pl-k"}],[{"start":2,"end":6,"cssClass":"pl-k"},{"start":7,"end":16,"cssClass":"pl-s"},{"start":7,"end":8,"cssClass":"pl-pds"},{"start":8,"end":15,"cssClass":"pl-smi"},{"start":15,"end":16,"cssClass":"pl-pds"},{"start":17,"end":19,"cssClass":"pl-k"}],[{"start":18,"end":24,"cssClass":"pl-s"},{"start":18,"end":19,"cssClass":"pl-pds"},{"start":23,"end":24,"cssClass":"pl-pds"}],[{"start":22,"end":33,"cssClass":"pl-s"},{"start":22,"end":23,"cssClass":"pl-pds"},{"start":23,"end":32,"cssClass":"pl-smi"},{"start":32,"end":33,"cssClass":"pl-pds"},{"start":38,"end":57,"cssClass":"pl-c"},{"start":38,"end":39,"cssClass":"pl-c"}],[{"start":25,"end":31,"cssClass":"pl-s"},{"start":25,"end":26,"cssClass":"pl-pds"},{"start":30,"end":31,"cssClass":"pl-pds"}],[{"start":18,"end":24,"cssClass":"pl-s"},{"start":18,"end":19,"cssClass":"pl-pds"},{"start":23,"end":24,"cssClass":"pl-pds"}],[{"start":26,"end":32,"cssClass":"pl-s"},{"start":26,"end":27,"cssClass":"pl-pds"},{"start":31,"end":32,"cssClass":"pl-pds"}],[{"start":19,"end":25,"cssClass":"pl-s"},{"start":19,"end":20,"cssClass":"pl-pds"},{"start":24,"end":25,"cssClass":"pl-pds"}],[],[{"start":16,"end":27,"cssClass":"pl-s"},{"start":16,"end":17,"cssClass":"pl-pds"},{"start":17,"end":26,"cssClass":"pl-smi"},{"start":26,"end":27,"cssClass":"pl-pds"}],[{"start":19,"end":33,"cssClass":"pl-s"},{"start":19,"end":20,"cssClass":"pl-pds"},{"start":20,"end":32,"cssClass":"pl-smi"},{"start":32,"end":33,"cssClass":"pl-pds"}],[{"start":20,"end":26,"cssClass":"pl-s"},{"start":20,"end":21,"cssClass":"pl-pds"},{"start":25,"end":26,"cssClass":"pl-pds"}],[{"start":4,"end":5,"cssClass":"pl-k"}],[{"start":6,"end":10,"cssClass":"pl-c1"},{"start":11,"end":39,"cssClass":"pl-s"},{"start":11,"end":12,"cssClass":"pl-pds"},{"start":38,"end":39,"cssClass":"pl-pds"}],[{"start":6,"end":10,"cssClass":"pl-c1"}],[{"start":2,"end":6,"cssClass":"pl-k"}],[{"start":0,"end":4,"cssClass":"pl-k"}],[],[{"start":0,"end":24,"cssClass":"pl-c"},{"start":0,"end":1,"cssClass":"pl-c"}],[{"start":0,"end":3,"cssClass":"pl-k"},{"start":4,"end":15,"cssClass":"pl-smi"},{"start":16,"end":18,"cssClass":"pl-k"},{"start":19,"end":39,"cssClass":"pl-s"},{"start":19,"end":20,"cssClass":"pl-pds"},{"start":20,"end":38,"cssClass":"pl-smi"},{"start":38,"end":39,"cssClass":"pl-pds"},{"start":39,"end":40,"cssClass":"pl-k"},{"start":41,"end":43,"cssClass":"pl-k"}],[{"start":2,"end":4,"cssClass":"pl-k"},{"start":8,"end":24,"cssClass":"pl-s"},{"start":8,"end":9,"cssClass":"pl-pds"},{"start":9,"end":23,"cssClass":"pl-smi"},{"start":23,"end":24,"cssClass":"pl-pds"},{"start":25,"end":27,"cssClass":"pl-k"},{"start":28,"end":41,"cssClass":"pl-s"},{"start":28,"end":29,"cssClass":"pl-pds"},{"start":40,"end":41,"cssClass":"pl-pds"},{"start":44,"end":45,"cssClass":"pl-k"},{"start":46,"end":50,"cssClass":"pl-k"},{"start":66,"end":72,"cssClass":"pl-s"},{"start":66,"end":67,"cssClass":"pl-pds"},{"start":71,"end":72,"cssClass":"pl-pds"},{"start":72,"end":73,"cssClass":"pl-k"},{"start":74,"end":76,"cssClass":"pl-k"}],[{"start":0,"end":4,"cssClass":"pl-k"}],[],[{"start":0,"end":14,"cssClass":"pl-c"},{"start":0,"end":1,"cssClass":"pl-c"}],[{"start":5,"end":21,"cssClass":"pl-s"},{"start":5,"end":6,"cssClass":"pl-pds"},{"start":20,"end":21,"cssClass":"pl-pds"}],[],[{"start":0,"end":18,"cssClass":"pl-c"},{"start":0,"end":1,"cssClass":"pl-c"}],[{"start":18,"end":50,"cssClass":"pl-s"},{"start":18,"end":19,"cssClass":"pl-pds"},{"start":49,"end":50,"cssClass":"pl-pds"}],[{"start":21,"end":42,"cssClass":"pl-s"},{"start":21,"end":22,"cssClass":"pl-pds"},{"start":41,"end":42,"cssClass":"pl-pds"}],[{"start":18,"end":106,"cssClass":"pl-s"},{"start":18,"end":19,"cssClass":"pl-pds"},{"start":105,"end":106,"cssClass":"pl-pds"}],[{"start":13,"end":248,"cssClass":"pl-s"},{"start":13,"end":14,"cssClass":"pl-pds"},{"start":247,"end":248,"cssClass":"pl-pds"}],[{"start":13,"end":60,"cssClass":"pl-s"},{"start":13,"end":14,"cssClass":"pl-pds"},{"start":59,"end":60,"cssClass":"pl-pds"}],[{"start":10,"end":81,"cssClass":"pl-s"},{"start":10,"end":11,"cssClass":"pl-pds"},{"start":80,"end":81,"cssClass":"pl-pds"}],[],[{"start":0,"end":34,"cssClass":"pl-c"},{"start":0,"end":1,"cssClass":"pl-c"}],[{"start":20,"end":105,"cssClass":"pl-s"},{"start":20,"end":21,"cssClass":"pl-pds"},{"start":104,"end":105,"cssClass":"pl-pds"}],[{"start":17,"end":91,"cssClass":"pl-s"},{"start":17,"end":18,"cssClass":"pl-pds"},{"start":90,"end":91,"cssClass":"pl-pds"}],[{"start":16,"end":104,"cssClass":"pl-s"},{"start":16,"end":17,"cssClass":"pl-pds"},{"start":103,"end":104,"cssClass":"pl-pds"}],[{"start":19,"end":85,"cssClass":"pl-s"},{"start":19,"end":20,"cssClass":"pl-pds"},{"start":84,"end":85,"cssClass":"pl-pds"}],[{"start":17,"end":67,"cssClass":"pl-s"},{"start":17,"end":18,"cssClass":"pl-pds"},{"start":66,"end":67,"cssClass":"pl-pds"}],[{"start":23,"end":100,"cssClass":"pl-s"},{"start":23,"end":24,"cssClass":"pl-pds"},{"start":99,"end":100,"cssClass":"pl-pds"}],[{"start":25,"end":109,"cssClass":"pl-s"},{"start":25,"end":26,"cssClass":"pl-pds"},{"start":108,"end":109,"cssClass":"pl-pds"}],[{"start":20,"end":100,"cssClass":"pl-s"},{"start":20,"end":21,"cssClass":"pl-pds"},{"start":99,"end":100,"cssClass":"pl-pds"}],[{"start":24,"end":111,"cssClass":"pl-s"},{"start":24,"end":25,"cssClass":"pl-pds"},{"start":110,"end":111,"cssClass":"pl-pds"}],[{"start":21,"end":97,"cssClass":"pl-s"},{"start":21,"end":22,"cssClass":"pl-pds"},{"start":96,"end":97,"cssClass":"pl-pds"}],[{"start":17,"end":95,"cssClass":"pl-s"},{"start":17,"end":18,"cssClass":"pl-pds"},{"start":94,"end":95,"cssClass":"pl-pds"}],[{"start":28,"end":138,"cssClass":"pl-s"},{"start":28,"end":29,"cssClass":"pl-pds"},{"start":137,"end":138,"cssClass":"pl-pds"}],[{"start":22,"end":86,"cssClass":"pl-s"},{"start":22,"end":23,"cssClass":"pl-pds"},{"start":85,"end":86,"cssClass":"pl-pds"}],[{"start":18,"end":99,"cssClass":"pl-s"},{"start":18,"end":19,"cssClass":"pl-pds"},{"start":98,"end":99,"cssClass":"pl-pds"}],[{"start":19,"end":89,"cssClass":"pl-s"},{"start":19,"end":20,"cssClass":"pl-pds"},{"start":88,"end":89,"cssClass":"pl-pds"}],[{"start":20,"end":123,"cssClass":"pl-s"},{"start":20,"end":21,"cssClass":"pl-pds"},{"start":122,"end":123,"cssClass":"pl-pds"}],[{"start":20,"end":93,"cssClass":"pl-s"},{"start":20,"end":21,"cssClass":"pl-pds"},{"start":92,"end":93,"cssClass":"pl-pds"}],[{"start":23,"end":85,"cssClass":"pl-s"},{"start":23,"end":24,"cssClass":"pl-pds"},{"start":84,"end":85,"cssClass":"pl-pds"}],[{"start":30,"end":120,"cssClass":"pl-s"},{"start":30,"end":31,"cssClass":"pl-pds"},{"start":119,"end":120,"cssClass":"pl-pds"}],[{"start":34,"end":105,"cssClass":"pl-s"},{"start":34,"end":35,"cssClass":"pl-pds"},{"start":104,"end":105,"cssClass":"pl-pds"}],[{"start":30,"end":117,"cssClass":"pl-s"},{"start":30,"end":31,"cssClass":"pl-pds"},{"start":116,"end":117,"cssClass":"pl-pds"}],[{"start":24,"end":88,"cssClass":"pl-s"},{"start":24,"end":25,"cssClass":"pl-pds"},{"start":87,"end":88,"cssClass":"pl-pds"}],[{"start":18,"end":163,"cssClass":"pl-s"},{"start":18,"end":19,"cssClass":"pl-pds"},{"start":162,"end":163,"cssClass":"pl-pds"}],[{"start":24,"end":183,"cssClass":"pl-s"},{"start":24,"end":25,"cssClass":"pl-pds"},{"start":182,"end":183,"cssClass":"pl-pds"}],[],[{"start":0,"end":22,"cssClass":"pl-c"},{"start":0,"end":1,"cssClass":"pl-c"}],[{"start":7,"end":96,"cssClass":"pl-s"},{"start":7,"end":8,"cssClass":"pl-pds"},{"start":95,"end":96,"cssClass":"pl-pds"}],[{"start":9,"end":109,"cssClass":"pl-s"},{"start":9,"end":10,"cssClass":"pl-pds"},{"start":108,"end":109,"cssClass":"pl-pds"}],[{"start":19,"end":84,"cssClass":"pl-s"},{"start":19,"end":20,"cssClass":"pl-pds"},{"start":83,"end":84,"cssClass":"pl-pds"}],[{"start":20,"end":95,"cssClass":"pl-s"},{"start":20,"end":21,"cssClass":"pl-pds"},{"start":94,"end":95,"cssClass":"pl-pds"}],[{"start":21,"end":86,"cssClass":"pl-s"},{"start":21,"end":22,"cssClass":"pl-pds"},{"start":85,"end":86,"cssClass":"pl-pds"}],[{"start":28,"end":89,"cssClass":"pl-s"},{"start":28,"end":29,"cssClass":"pl-pds"},{"start":88,"end":89,"cssClass":"pl-pds"}],[],[{"start":0,"end":28,"cssClass":"pl-c"},{"start":0,"end":1,"cssClass":"pl-c"}],[{"start":16,"end":361,"cssClass":"pl-s"},{"start":16,"end":17,"cssClass":"pl-pds"},{"start":360,"end":361,"cssClass":"pl-pds"}],[{"start":13,"end":52,"cssClass":"pl-s"},{"start":13,"end":14,"cssClass":"pl-pds"},{"start":51,"end":52,"cssClass":"pl-pds"}],[{"start":13,"end":79,"cssClass":"pl-s"},{"start":13,"end":14,"cssClass":"pl-pds"},{"start":78,"end":79,"cssClass":"pl-pds"}],[{"start":15,"end":89,"cssClass":"pl-s"},{"start":15,"end":16,"cssClass":"pl-pds"},{"start":88,"end":89,"cssClass":"pl-pds"}],[],[{"start":0,"end":50,"cssClass":"pl-c"},{"start":0,"end":1,"cssClass":"pl-c"}],[{"start":14,"end":238,"cssClass":"pl-s"},{"start":14,"end":15,"cssClass":"pl-pds"},{"start":237,"end":238,"cssClass":"pl-pds"}],[{"start":15,"end":88,"cssClass":"pl-s"},{"start":15,"end":16,"cssClass":"pl-pds"},{"start":87,"end":88,"cssClass":"pl-pds"},{"start":88,"end":90,"cssClass":"pl-cce"},{"start":90,"end":99,"cssClass":"pl-s"},{"start":90,"end":91,"cssClass":"pl-pds"},{"start":98,"end":99,"cssClass":"pl-pds"},{"start":99,"end":101,"cssClass":"pl-cce"},{"start":101,"end":133,"cssClass":"pl-s"},{"start":101,"end":102,"cssClass":"pl-pds"},{"start":132,"end":133,"cssClass":"pl-pds"},{"start":133,"end":135,"cssClass":"pl-cce"},{"start":135,"end":141,"cssClass":"pl-s"},{"start":135,"end":136,"cssClass":"pl-pds"},{"start":140,"end":141,"cssClass":"pl-pds"},{"start":141,"end":143,"cssClass":"pl-cce"},{"start":143,"end":147,"cssClass":"pl-s"},{"start":143,"end":144,"cssClass":"pl-pds"},{"start":146,"end":147,"cssClass":"pl-pds"}],[{"start":15,"end":79,"cssClass":"pl-s"},{"start":15,"end":16,"cssClass":"pl-pds"},{"start":78,"end":79,"cssClass":"pl-pds"},{"start":79,"end":81,"cssClass":"pl-cce"},{"start":81,"end":90,"cssClass":"pl-s"},{"start":81,"end":82,"cssClass":"pl-pds"},{"start":89,"end":90,"cssClass":"pl-pds"},{"start":90,"end":92,"cssClass":"pl-cce"},{"start":92,"end":115,"cssClass":"pl-s"},{"start":92,"end":93,"cssClass":"pl-pds"},{"start":114,"end":115,"cssClass":"pl-pds"},{"start":115,"end":117,"cssClass":"pl-cce"},{"start":117,"end":123,"cssClass":"pl-s"},{"start":117,"end":118,"cssClass":"pl-pds"},{"start":122,"end":123,"cssClass":"pl-pds"},{"start":123,"end":125,"cssClass":"pl-cce"},{"start":125,"end":129,"cssClass":"pl-s"},{"start":125,"end":126,"cssClass":"pl-pds"},{"start":128,"end":129,"cssClass":"pl-pds"}],[],[{"start":0,"end":19,"cssClass":"pl-c"},{"start":0,"end":1,"cssClass":"pl-c"}],[{"start":6,"end":32,"cssClass":"pl-s"},{"start":6,"end":7,"cssClass":"pl-pds"},{"start":31,"end":32,"cssClass":"pl-pds"}],[{"start":11,"end":57,"cssClass":"pl-s"},{"start":11,"end":12,"cssClass":"pl-pds"},{"start":56,"end":57,"cssClass":"pl-pds"}],[],[{"start":0,"end":29,"cssClass":"pl-c"},{"start":0,"end":1,"cssClass":"pl-c"}],[{"start":14,"end":55,"cssClass":"pl-s"},{"start":14,"end":15,"cssClass":"pl-pds"},{"start":54,"end":55,"cssClass":"pl-pds"},{"start":56,"end":69,"cssClass":"pl-c"},{"start":56,"end":57,"cssClass":"pl-c"}],[{"start":14,"end":72,"cssClass":"pl-s"},{"start":14,"end":15,"cssClass":"pl-pds"},{"start":71,"end":72,"cssClass":"pl-pds"},{"start":73,"end":86,"cssClass":"pl-c"},{"start":73,"end":74,"cssClass":"pl-c"}],[{"start":14,"end":54,"cssClass":"pl-s"},{"start":14,"end":15,"cssClass":"pl-pds"},{"start":53,"end":54,"cssClass":"pl-pds"},{"start":55,"end":68,"cssClass":"pl-c"},{"start":55,"end":56,"cssClass":"pl-c"}],[{"start":12,"end":91,"cssClass":"pl-s"},{"start":12,"end":13,"cssClass":"pl-pds"},{"start":90,"end":91,"cssClass":"pl-pds"},{"start":92,"end":105,"cssClass":"pl-c"},{"start":92,"end":93,"cssClass":"pl-c"}],[{"start":18,"end":96,"cssClass":"pl-s"},{"start":18,"end":19,"cssClass":"pl-pds"},{"start":95,"end":96,"cssClass":"pl-pds"},{"start":97,"end":122,"cssClass":"pl-c"},{"start":97,"end":98,"cssClass":"pl-c"}],[{"start":18,"end":97,"cssClass":"pl-s"},{"start":18,"end":19,"cssClass":"pl-pds"},{"start":96,"end":97,"cssClass":"pl-pds"},{"start":98,"end":123,"cssClass":"pl-c"},{"start":98,"end":99,"cssClass":"pl-c"}],[],[{"start":0,"end":9,"cssClass":"pl-c"},{"start":0,"end":1,"cssClass":"pl-c"}],[{"start":0,"end":4,"cssClass":"pl-c1"}],[{"start":0,"end":4,"cssClass":"pl-c1"},{"start":5,"end":33,"cssClass":"pl-s"},{"start":5,"end":6,"cssClass":"pl-pds"},{"start":32,"end":33,"cssClass":"pl-pds"}],[{"start":0,"end":4,"cssClass":"pl-c1"},{"start":5,"end":32,"cssClass":"pl-s"},{"start":5,"end":6,"cssClass":"pl-pds"},{"start":31,"end":32,"cssClass":"pl-pds"}],[{"start":0,"end":4,"cssClass":"pl-c1"},{"start":5,"end":33,"cssClass":"pl-s"},{"start":5,"end":6,"cssClass":"pl-pds"},{"start":32,"end":33,"cssClass":"pl-pds"}],[{"start":0,"end":4,"cssClass":"pl-c1"}],[],[{"start":0,"end":22,"cssClass":"pl-c"},{"start":0,"end":1,"cssClass":"pl-c"}],[{"start":0,"end":4,"cssClass":"pl-c1"},{"start":8,"end":49,"cssClass":"pl-s"},{"start":8,"end":9,"cssClass":"pl-pds"},{"start":30,"end":46,"cssClass":"pl-smi"},{"start":48,"end":49,"cssClass":"pl-pds"}],[],[{"start":0,"end":26,"cssClass":"pl-c"},{"start":0,"end":1,"cssClass":"pl-c"}],[{"start":0,"end":2,"cssClass":"pl-k"},{"start":5,"end":7,"cssClass":"pl-k"},{"start":8,"end":25,"cssClass":"pl-smi"},{"start":27,"end":28,"cssClass":"pl-k"},{"start":29,"end":33,"cssClass":"pl-k"}],[{"start":15,"end":86,"cssClass":"pl-s"},{"start":15,"end":17,"cssClass":"pl-pds"},{"start":29,"end":46,"cssClass":"pl-s"},{"start":29,"end":30,"cssClass":"pl-pds"},{"start":45,"end":46,"cssClass":"pl-pds"},{"start":47,"end":49,"cssClass":"pl-k"},{"start":59,"end":60,"cssClass":"pl-k"},{"start":65,"end":66,"cssClass":"pl-k"},{"start":80,"end":81,"cssClass":"pl-k"},{"start":85,"end":86,"cssClass":"pl-pds"}],[{"start":2,"end":4,"cssClass":"pl-k"},{"start":8,"end":10,"cssClass":"pl-k"},{"start":11,"end":28,"cssClass":"pl-s"},{"start":11,"end":12,"cssClass":"pl-pds"},{"start":12,"end":27,"cssClass":"pl-smi"},{"start":27,"end":28,"cssClass":"pl-pds"},{"start":29,"end":31,"cssClass":"pl-k"},{"start":32,"end":49,"cssClass":"pl-s"},{"start":32,"end":33,"cssClass":"pl-pds"},{"start":33,"end":48,"cssClass":"pl-smi"},{"start":48,"end":49,"cssClass":"pl-pds"},{"start":50,"end":52,"cssClass":"pl-k"},{"start":53,"end":63,"cssClass":"pl-s"},{"start":53,"end":54,"cssClass":"pl-pds"},{"start":62,"end":63,"cssClass":"pl-pds"},{"start":66,"end":67,"cssClass":"pl-k"},{"start":68,"end":72,"cssClass":"pl-k"}],[{"start":4,"end":8,"cssClass":"pl-c1"},{"start":9,"end":59,"cssClass":"pl-s"},{"start":9,"end":10,"cssClass":"pl-pds"},{"start":43,"end":58,"cssClass":"pl-smi"},{"start":58,"end":59,"cssClass":"pl-pds"}],[{"start":2,"end":6,"cssClass":"pl-k"},{"start":10,"end":11,"cssClass":"pl-k"},{"start":12,"end":14,"cssClass":"pl-k"},{"start":15,"end":32,"cssClass":"pl-s"},{"start":15,"end":16,"cssClass":"pl-pds"},{"start":16,"end":31,"cssClass":"pl-smi"},{"start":31,"end":32,"cssClass":"pl-pds"},{"start":35,"end":36,"cssClass":"pl-k"},{"start":37,"end":41,"cssClass":"pl-k"}],[{"start":4,"end":8,"cssClass":"pl-c1"},{"start":12,"end":77,"cssClass":"pl-s"},{"start":12,"end":13,"cssClass":"pl-pds"},{"start":76,"end":77,"cssClass":"pl-pds"}],[{"start":17,"end":159,"cssClass":"pl-s"},{"start":17,"end":19,"cssClass":"pl-pds"},{"start":51,"end":69,"cssClass":"pl-s"},{"start":51,"end":52,"cssClass":"pl-pds"},{"start":68,"end":69,"cssClass":"pl-pds"},{"start":76,"end":86,"cssClass":"pl-s"},{"start":76,"end":77,"cssClass":"pl-pds"},{"start":85,"end":86,"cssClass":"pl-pds"},{"start":120,"end":122,"cssClass":"pl-k"},{"start":132,"end":133,"cssClass":"pl-k"},{"start":138,"end":139,"cssClass":"pl-k"},{"start":153,"end":154,"cssClass":"pl-k"},{"start":158,"end":159,"cssClass":"pl-pds"}],[{"start":4,"end":6,"cssClass":"pl-k"},{"start":10,"end":12,"cssClass":"pl-k"},{"start":13,"end":30,"cssClass":"pl-s"},{"start":13,"end":14,"cssClass":"pl-pds"},{"start":14,"end":29,"cssClass":"pl-smi"},{"start":29,"end":30,"cssClass":"pl-pds"},{"start":33,"end":34,"cssClass":"pl-k"},{"start":35,"end":39,"cssClass":"pl-k"}],[{"start":6,"end":10,"cssClass":"pl-c1"},{"start":11,"end":53,"cssClass":"pl-s"},{"start":11,"end":12,"cssClass":"pl-pds"},{"start":37,"end":52,"cssClass":"pl-smi"},{"start":52,"end":53,"cssClass":"pl-pds"}],[{"start":4,"end":8,"cssClass":"pl-k"},{"start":12,"end":13,"cssClass":"pl-k"},{"start":14,"end":16,"cssClass":"pl-k"},{"start":17,"end":34,"cssClass":"pl-s"},{"start":17,"end":18,"cssClass":"pl-pds"},{"start":18,"end":33,"cssClass":"pl-smi"},{"start":33,"end":34,"cssClass":"pl-pds"},{"start":37,"end":38,"cssClass":"pl-k"},{"start":39,"end":43,"cssClass":"pl-k"}],[{"start":6,"end":10,"cssClass":"pl-c1"},{"start":14,"end":91,"cssClass":"pl-s"},{"start":14,"end":15,"cssClass":"pl-pds"},{"start":90,"end":91,"cssClass":"pl-pds"}],[{"start":6,"end":10,"cssClass":"pl-c1"},{"start":10,"end":11,"cssClass":"pl-k"},{"start":12,"end":14,"cssClass":"pl-k"}],[{"start":2,"end":6,"cssClass":"pl-k"},{"start":10,"end":27,"cssClass":"pl-s"},{"start":10,"end":11,"cssClass":"pl-pds"},{"start":11,"end":26,"cssClass":"pl-smi"},{"start":26,"end":27,"cssClass":"pl-pds"},{"start":28,"end":30,"cssClass":"pl-k"},{"start":31,"end":41,"cssClass":"pl-s"},{"start":31,"end":32,"cssClass":"pl-pds"},{"start":40,"end":41,"cssClass":"pl-pds"},{"start":44,"end":45,"cssClass":"pl-k"},{"start":46,"end":50,"cssClass":"pl-k"}],[{"start":4,"end":8,"cssClass":"pl-c1"},{"start":12,"end":83,"cssClass":"pl-s"},{"start":12,"end":13,"cssClass":"pl-pds"},{"start":82,"end":83,"cssClass":"pl-pds"}],[{"start":17,"end":159,"cssClass":"pl-s"},{"start":17,"end":19,"cssClass":"pl-pds"},{"start":51,"end":69,"cssClass":"pl-s"},{"start":51,"end":52,"cssClass":"pl-pds"},{"start":68,"end":69,"cssClass":"pl-pds"},{"start":76,"end":86,"cssClass":"pl-s"},{"start":76,"end":77,"cssClass":"pl-pds"},{"start":85,"end":86,"cssClass":"pl-pds"},{"start":120,"end":122,"cssClass":"pl-k"},{"start":132,"end":133,"cssClass":"pl-k"},{"start":138,"end":139,"cssClass":"pl-k"},{"start":153,"end":154,"cssClass":"pl-k"},{"start":158,"end":159,"cssClass":"pl-pds"}],[{"start":4,"end":6,"cssClass":"pl-k"},{"start":10,"end":12,"cssClass":"pl-k"},{"start":13,"end":30,"cssClass":"pl-s"},{"start":13,"end":14,"cssClass":"pl-pds"},{"start":14,"end":29,"cssClass":"pl-smi"},{"start":29,"end":30,"cssClass":"pl-pds"},{"start":31,"end":33,"cssClass":"pl-k"},{"start":34,"end":51,"cssClass":"pl-s"},{"start":34,"end":35,"cssClass":"pl-pds"},{"start":35,"end":50,"cssClass":"pl-smi"},{"start":50,"end":51,"cssClass":"pl-pds"},{"start":52,"end":54,"cssClass":"pl-k"},{"start":55,"end":65,"cssClass":"pl-s"},{"start":55,"end":56,"cssClass":"pl-pds"},{"start":64,"end":65,"cssClass":"pl-pds"},{"start":68,"end":69,"cssClass":"pl-k"},{"start":70,"end":74,"cssClass":"pl-k"}],[{"start":6,"end":10,"cssClass":"pl-c1"},{"start":11,"end":53,"cssClass":"pl-s"},{"start":11,"end":12,"cssClass":"pl-pds"},{"start":37,"end":52,"cssClass":"pl-smi"},{"start":52,"end":53,"cssClass":"pl-pds"}],[{"start":4,"end":8,"cssClass":"pl-k"},{"start":12,"end":29,"cssClass":"pl-s"},{"start":12,"end":13,"cssClass":"pl-pds"},{"start":13,"end":28,"cssClass":"pl-smi"},{"start":28,"end":29,"cssClass":"pl-pds"},{"start":30,"end":32,"cssClass":"pl-k"},{"start":33,"end":43,"cssClass":"pl-s"},{"start":33,"end":34,"cssClass":"pl-pds"},{"start":42,"end":43,"cssClass":"pl-pds"},{"start":47,"end":49,"cssClass":"pl-k"},{"start":53,"end":54,"cssClass":"pl-k"},{"start":55,"end":57,"cssClass":"pl-k"},{"start":58,"end":75,"cssClass":"pl-s"},{"start":58,"end":59,"cssClass":"pl-pds"},{"start":59,"end":74,"cssClass":"pl-smi"},{"start":74,"end":75,"cssClass":"pl-pds"},{"start":78,"end":79,"cssClass":"pl-k"},{"start":80,"end":84,"cssClass":"pl-k"}],[{"start":6,"end":10,"cssClass":"pl-c1"},{"start":14,"end":91,"cssClass":"pl-s"},{"start":14,"end":15,"cssClass":"pl-pds"},{"start":90,"end":91,"cssClass":"pl-pds"}],[{"start":6,"end":10,"cssClass":"pl-c1"},{"start":10,"end":11,"cssClass":"pl-k"},{"start":12,"end":14,"cssClass":"pl-k"},{"start":14,"end":15,"cssClass":"pl-k"},{"start":16,"end":18,"cssClass":"pl-k"}],[{"start":0,"end":4,"cssClass":"pl-k"}],[{"start":2,"end":4,"cssClass":"pl-k"},{"start":8,"end":9,"cssClass":"pl-k"},{"start":10,"end":12,"cssClass":"pl-k"},{"start":13,"end":30,"cssClass":"pl-s"},{"start":13,"end":14,"cssClass":"pl-pds"},{"start":14,"end":29,"cssClass":"pl-smi"},{"start":29,"end":30,"cssClass":"pl-pds"},{"start":33,"end":34,"cssClass":"pl-k"},{"start":35,"end":39,"cssClass":"pl-k"}],[{"start":4,"end":8,"cssClass":"pl-c1"},{"start":12,"end":67,"cssClass":"pl-s"},{"start":12,"end":13,"cssClass":"pl-pds"},{"start":66,"end":67,"cssClass":"pl-pds"}],[{"start":4,"end":8,"cssClass":"pl-c1"}],[{"start":2,"end":6,"cssClass":"pl-k"},{"start":10,"end":11,"cssClass":"pl-k"},{"start":12,"end":14,"cssClass":"pl-k"},{"start":15,"end":46,"cssClass":"pl-s"},{"start":15,"end":16,"cssClass":"pl-pds"},{"start":16,"end":31,"cssClass":"pl-smi"},{"start":45,"end":46,"cssClass":"pl-pds"},{"start":49,"end":50,"cssClass":"pl-k"},{"start":51,"end":55,"cssClass":"pl-k"}],[{"start":4,"end":8,"cssClass":"pl-c1"},{"start":12,"end":135,"cssClass":"pl-s"},{"start":12,"end":13,"cssClass":"pl-pds"},{"start":134,"end":135,"cssClass":"pl-pds"}],[{"start":4,"end":8,"cssClass":"pl-c1"},{"start":8,"end":9,"cssClass":"pl-k"},{"start":10,"end":12,"cssClass":"pl-k"},{"start":12,"end":13,"cssClass":"pl-k"},{"start":14,"end":16,"cssClass":"pl-k"}],[],[{"start":0,"end":21,"cssClass":"pl-c"},{"start":0,"end":1,"cssClass":"pl-c"}],[{"start":15,"end":95,"cssClass":"pl-s"},{"start":15,"end":17,"cssClass":"pl-pds"},{"start":17,"end":34,"cssClass":"pl-s"},{"start":17,"end":18,"cssClass":"pl-pds"},{"start":18,"end":33,"cssClass":"pl-smi"},{"start":33,"end":34,"cssClass":"pl-pds"},{"start":53,"end":54,"cssClass":"pl-k"},{"start":68,"end":69,"cssClass":"pl-k"},{"start":74,"end":75,"cssClass":"pl-k"},{"start":89,"end":90,"cssClass":"pl-k"},{"start":94,"end":95,"cssClass":"pl-pds"}],[],[{"start":0,"end":41,"cssClass":"pl-c"},{"start":0,"end":1,"cssClass":"pl-c"}],[{"start":0,"end":8,"cssClass":"pl-k"},{"start":9,"end":12,"cssClass":"pl-en"},{"start":15,"end":19,"cssClass":"pl-c1"},{"start":20,"end":24,"cssClass":"pl-s"},{"start":20,"end":21,"cssClass":"pl-pds"},{"start":21,"end":23,"cssClass":"pl-smi"},{"start":23,"end":24,"cssClass":"pl-pds"},{"start":25,"end":26,"cssClass":"pl-k"},{"start":35,"end":81,"cssClass":"pl-s"},{"start":35,"end":36,"cssClass":"pl-pds"},{"start":80,"end":81,"cssClass":"pl-pds"},{"start":81,"end":82,"cssClass":"pl-k"}],[],[{"start":0,"end":24,"cssClass":"pl-c"},{"start":0,"end":1,"cssClass":"pl-c"}],[{"start":0,"end":4,"cssClass":"pl-c1"},{"start":8,"end":48,"cssClass":"pl-s"},{"start":8,"end":9,"cssClass":"pl-pds"},{"start":28,"end":45,"cssClass":"pl-smi"},{"start":47,"end":48,"cssClass":"pl-pds"}],[],[{"start":0,"end":11,"cssClass":"pl-c"},{"start":0,"end":1,"cssClass":"pl-c"}],[{"start":11,"end":36,"cssClass":"pl-s"},{"start":11,"end":12,"cssClass":"pl-pds"},{"start":12,"end":19,"cssClass":"pl-smi"},{"start":35,"end":36,"cssClass":"pl-pds"}],[{"start":10,"end":32,"cssClass":"pl-s"},{"start":10,"end":11,"cssClass":"pl-pds"},{"start":11,"end":26,"cssClass":"pl-smi"},{"start":31,"end":32,"cssClass":"pl-pds"}],[{"start":9,"end":28,"cssClass":"pl-s"},{"start":9,"end":10,"cssClass":"pl-pds"},{"start":10,"end":22,"cssClass":"pl-smi"},{"start":27,"end":28,"cssClass":"pl-pds"}],[{"start":9,"end":32,"cssClass":"pl-s"},{"start":9,"end":10,"cssClass":"pl-pds"},{"start":10,"end":22,"cssClass":"pl-smi"},{"start":31,"end":32,"cssClass":"pl-pds"}],[{"start":9,"end":32,"cssClass":"pl-s"},{"start":9,"end":10,"cssClass":"pl-pds"},{"start":10,"end":22,"cssClass":"pl-smi"},{"start":31,"end":32,"cssClass":"pl-pds"}],[{"start":8,"end":29,"cssClass":"pl-s"},{"start":8,"end":9,"cssClass":"pl-pds"},{"start":9,"end":20,"cssClass":"pl-smi"},{"start":28,"end":29,"cssClass":"pl-pds"}],[{"start":9,"end":31,"cssClass":"pl-s"},{"start":9,"end":10,"cssClass":"pl-pds"},{"start":10,"end":21,"cssClass":"pl-smi"},{"start":30,"end":31,"cssClass":"pl-pds"}],[{"start":11,"end":35,"cssClass":"pl-s"},{"start":11,"end":12,"cssClass":"pl-pds"},{"start":12,"end":23,"cssClass":"pl-smi"},{"start":34,"end":35,"cssClass":"pl-pds"}],[{"start":15,"end":43,"cssClass":"pl-s"},{"start":15,"end":16,"cssClass":"pl-pds"},{"start":16,"end":27,"cssClass":"pl-smi"},{"start":42,"end":43,"cssClass":"pl-pds"}],[],[{"start":0,"end":16,"cssClass":"pl-c"},{"start":0,"end":1,"cssClass":"pl-c"}],[{"start":0,"end":2,"cssClass":"pl-k"},{"start":6,"end":7,"cssClass":"pl-k"},{"start":8,"end":10,"cssClass":"pl-k"},{"start":11,"end":24,"cssClass":"pl-s"},{"start":11,"end":12,"cssClass":"pl-pds"},{"start":12,"end":23,"cssClass":"pl-smi"},{"start":23,"end":24,"cssClass":"pl-pds"},{"start":27,"end":28,"cssClass":"pl-k"},{"start":29,"end":33,"cssClass":"pl-k"}],[{"start":2,"end":6,"cssClass":"pl-c1"},{"start":10,"end":78,"cssClass":"pl-s"},{"start":10,"end":11,"cssClass":"pl-pds"},{"start":77,"end":78,"cssClass":"pl-pds"}],[{"start":2,"end":6,"cssClass":"pl-c1"}],[{"start":0,"end":4,"cssClass":"pl-k"}],[{"start":2,"end":4,"cssClass":"pl-k"},{"start":8,"end":9,"cssClass":"pl-k"},{"start":10,"end":12,"cssClass":"pl-k"},{"start":13,"end":27,"cssClass":"pl-s"},{"start":13,"end":14,"cssClass":"pl-pds"},{"start":14,"end":26,"cssClass":"pl-smi"},{"start":26,"end":27,"cssClass":"pl-pds"},{"start":30,"end":31,"cssClass":"pl-k"},{"start":32,"end":36,"cssClass":"pl-k"}],[{"start":4,"end":8,"cssClass":"pl-c1"},{"start":12,"end":107,"cssClass":"pl-s"},{"start":12,"end":13,"cssClass":"pl-pds"},{"start":106,"end":107,"cssClass":"pl-pds"}],[{"start":20,"end":37,"cssClass":"pl-s"},{"start":20,"end":21,"cssClass":"pl-pds"},{"start":21,"end":36,"cssClass":"pl-smi"},{"start":36,"end":37,"cssClass":"pl-pds"},{"start":38,"end":40,"cssClass":"pl-k"},{"start":60,"end":74,"cssClass":"pl-s"},{"start":60,"end":61,"cssClass":"pl-pds"},{"start":61,"end":73,"cssClass":"pl-smi"},{"start":73,"end":74,"cssClass":"pl-pds"},{"start":74,"end":75,"cssClass":"pl-k"},{"start":76,"end":78,"cssClass":"pl-k"}],[{"start":2,"end":4,"cssClass":"pl-k"},{"start":8,"end":23,"cssClass":"pl-s"},{"start":8,"end":9,"cssClass":"pl-pds"},{"start":9,"end":22,"cssClass":"pl-smi"},{"start":22,"end":23,"cssClass":"pl-pds"},{"start":24,"end":26,"cssClass":"pl-k"},{"start":27,"end":34,"cssClass":"pl-s"},{"start":27,"end":28,"cssClass":"pl-pds"},{"start":33,"end":34,"cssClass":"pl-pds"},{"start":37,"end":38,"cssClass":"pl-k"},{"start":39,"end":43,"cssClass":"pl-k"}],[{"start":4,"end":6,"cssClass":"pl-k"},{"start":10,"end":12,"cssClass":"pl-k"},{"start":13,"end":26,"cssClass":"pl-s"},{"start":13,"end":14,"cssClass":"pl-pds"},{"start":14,"end":25,"cssClass":"pl-smi"},{"start":25,"end":26,"cssClass":"pl-pds"},{"start":29,"end":30,"cssClass":"pl-k"},{"start":31,"end":35,"cssClass":"pl-k"}],[{"start":6,"end":10,"cssClass":"pl-c1"},{"start":11,"end":77,"cssClass":"pl-s"},{"start":11,"end":12,"cssClass":"pl-pds"},{"start":76,"end":77,"cssClass":"pl-pds"}],[{"start":6,"end":10,"cssClass":"pl-c1"},{"start":14,"end":74,"cssClass":"pl-s"},{"start":14,"end":15,"cssClass":"pl-pds"},{"start":73,"end":74,"cssClass":"pl-pds"}],[{"start":6,"end":10,"cssClass":"pl-c1"},{"start":11,"end":58,"cssClass":"pl-s"},{"start":11,"end":12,"cssClass":"pl-pds"},{"start":57,"end":58,"cssClass":"pl-pds"}],[{"start":16,"end":22,"cssClass":"pl-s"},{"start":16,"end":17,"cssClass":"pl-pds"},{"start":21,"end":22,"cssClass":"pl-pds"}],[{"start":4,"end":8,"cssClass":"pl-k"}],[{"start":6,"end":10,"cssClass":"pl-c1"},{"start":11,"end":36,"cssClass":"pl-s"},{"start":11,"end":12,"cssClass":"pl-pds"},{"start":35,"end":36,"cssClass":"pl-pds"}],[{"start":9,"end":22,"cssClass":"pl-s"},{"start":9,"end":10,"cssClass":"pl-pds"},{"start":10,"end":21,"cssClass":"pl-smi"},{"start":21,"end":22,"cssClass":"pl-pds"},{"start":23,"end":36,"cssClass":"pl-s"},{"start":23,"end":24,"cssClass":"pl-pds"},{"start":24,"end":35,"cssClass":"pl-smi"},{"start":35,"end":36,"cssClass":"pl-pds"}],[{"start":16,"end":23,"cssClass":"pl-s"},{"start":16,"end":17,"cssClass":"pl-pds"},{"start":22,"end":23,"cssClass":"pl-pds"},{"start":23,"end":24,"cssClass":"pl-k"},{"start":25,"end":27,"cssClass":"pl-k"}],[{"start":2,"end":6,"cssClass":"pl-k"}],[{"start":4,"end":6,"cssClass":"pl-k"},{"start":10,"end":12,"cssClass":"pl-k"},{"start":13,"end":26,"cssClass":"pl-s"},{"start":13,"end":14,"cssClass":"pl-pds"},{"start":14,"end":25,"cssClass":"pl-smi"},{"start":25,"end":26,"cssClass":"pl-pds"},{"start":29,"end":30,"cssClass":"pl-k"},{"start":31,"end":35,"cssClass":"pl-k"}],[{"start":6,"end":10,"cssClass":"pl-c1"},{"start":11,"end":53,"cssClass":"pl-s"},{"start":11,"end":12,"cssClass":"pl-pds"},{"start":52,"end":53,"cssClass":"pl-pds"}],[{"start":9,"end":22,"cssClass":"pl-s"},{"start":9,"end":10,"cssClass":"pl-pds"},{"start":10,"end":21,"cssClass":"pl-smi"},{"start":21,"end":22,"cssClass":"pl-pds"}],[{"start":9,"end":22,"cssClass":"pl-s"},{"start":9,"end":10,"cssClass":"pl-pds"},{"start":10,"end":21,"cssClass":"pl-smi"},{"start":21,"end":22,"cssClass":"pl-pds"},{"start":23,"end":36,"cssClass":"pl-s"},{"start":23,"end":24,"cssClass":"pl-pds"},{"start":24,"end":35,"cssClass":"pl-smi"},{"start":35,"end":36,"cssClass":"pl-pds"}],[{"start":16,"end":23,"cssClass":"pl-s"},{"start":16,"end":17,"cssClass":"pl-pds"},{"start":22,"end":23,"cssClass":"pl-pds"}],[{"start":4,"end":8,"cssClass":"pl-k"}],[{"start":6,"end":10,"cssClass":"pl-c1"},{"start":11,"end":36,"cssClass":"pl-s"},{"start":11,"end":12,"cssClass":"pl-pds"},{"start":35,"end":36,"cssClass":"pl-pds"}],[{"start":9,"end":22,"cssClass":"pl-s"},{"start":9,"end":10,"cssClass":"pl-pds"},{"start":10,"end":21,"cssClass":"pl-smi"},{"start":21,"end":22,"cssClass":"pl-pds"},{"start":23,"end":36,"cssClass":"pl-s"},{"start":23,"end":24,"cssClass":"pl-pds"},{"start":24,"end":35,"cssClass":"pl-smi"},{"start":35,"end":36,"cssClass":"pl-pds"}],[{"start":16,"end":23,"cssClass":"pl-s"},{"start":16,"end":17,"cssClass":"pl-pds"},{"start":22,"end":23,"cssClass":"pl-pds"},{"start":23,"end":24,"cssClass":"pl-k"},{"start":25,"end":27,"cssClass":"pl-k"},{"start":27,"end":28,"cssClass":"pl-k"},{"start":29,"end":31,"cssClass":"pl-k"},{"start":31,"end":32,"cssClass":"pl-k"},{"start":33,"end":35,"cssClass":"pl-k"}],[],[{"start":0,"end":18,"cssClass":"pl-c"},{"start":0,"end":1,"cssClass":"pl-c"}],[{"start":0,"end":2,"cssClass":"pl-k"},{"start":6,"end":20,"cssClass":"pl-s"},{"start":6,"end":7,"cssClass":"pl-pds"},{"start":7,"end":19,"cssClass":"pl-smi"},{"start":19,"end":20,"cssClass":"pl-pds"},{"start":21,"end":23,"cssClass":"pl-k"},{"start":24,"end":31,"cssClass":"pl-s"},{"start":24,"end":25,"cssClass":"pl-pds"},{"start":30,"end":31,"cssClass":"pl-pds"},{"start":34,"end":35,"cssClass":"pl-k"},{"start":36,"end":40,"cssClass":"pl-k"}],[{"start":2,"end":6,"cssClass":"pl-c1"},{"start":7,"end":27,"cssClass":"pl-s"},{"start":7,"end":8,"cssClass":"pl-pds"},{"start":26,"end":27,"cssClass":"pl-pds"}],[{"start":12,"end":25,"cssClass":"pl-s"},{"start":12,"end":13,"cssClass":"pl-pds"},{"start":13,"end":24,"cssClass":"pl-smi"},{"start":24,"end":25,"cssClass":"pl-pds"},{"start":29,"end":42,"cssClass":"pl-s"},{"start":29,"end":30,"cssClass":"pl-pds"},{"start":30,"end":41,"cssClass":"pl-smi"},{"start":41,"end":42,"cssClass":"pl-pds"}],[{"start":2,"end":4,"cssClass":"pl-k"},{"start":14,"end":21,"cssClass":"pl-s"},{"start":14,"end":15,"cssClass":"pl-pds"},{"start":20,"end":21,"cssClass":"pl-pds"},{"start":22,"end":34,"cssClass":"pl-s"},{"start":22,"end":23,"cssClass":"pl-pds"},{"start":23,"end":33,"cssClass":"pl-smi"},{"start":33,"end":34,"cssClass":"pl-pds"},{"start":34,"end":35,"cssClass":"pl-k"},{"start":36,"end":40,"cssClass":"pl-k"}],[{"start":4,"end":8,"cssClass":"pl-c1"},{"start":12,"end":67,"cssClass":"pl-s"},{"start":12,"end":13,"cssClass":"pl-pds"},{"start":66,"end":67,"cssClass":"pl-pds"}],[{"start":4,"end":8,"cssClass":"pl-c1"},{"start":12,"end":88,"cssClass":"pl-s"},{"start":12,"end":13,"cssClass":"pl-pds"},{"start":87,"end":88,"cssClass":"pl-pds"}],[{"start":4,"end":8,"cssClass":"pl-c1"},{"start":9,"end":56,"cssClass":"pl-s"},{"start":9,"end":10,"cssClass":"pl-pds"},{"start":55,"end":56,"cssClass":"pl-pds"}],[{"start":14,"end":20,"cssClass":"pl-s"},{"start":14,"end":15,"cssClass":"pl-pds"},{"start":19,"end":20,"cssClass":"pl-pds"}],[{"start":7,"end":20,"cssClass":"pl-s"},{"start":7,"end":8,"cssClass":"pl-pds"},{"start":8,"end":19,"cssClass":"pl-smi"},{"start":19,"end":20,"cssClass":"pl-pds"},{"start":21,"end":23,"cssClass":"pl-k"}],[{"start":11,"end":24,"cssClass":"pl-s"},{"start":11,"end":12,"cssClass":"pl-pds"},{"start":12,"end":23,"cssClass":"pl-smi"},{"start":23,"end":24,"cssClass":"pl-pds"},{"start":25,"end":27,"cssClass":"pl-k"}],[{"start":2,"end":6,"cssClass":"pl-k"}],[{"start":7,"end":20,"cssClass":"pl-s"},{"start":7,"end":8,"cssClass":"pl-pds"},{"start":8,"end":19,"cssClass":"pl-smi"},{"start":19,"end":20,"cssClass":"pl-pds"},{"start":20,"end":21,"cssClass":"pl-k"},{"start":22,"end":24,"cssClass":"pl-k"},{"start":24,"end":25,"cssClass":"pl-k"},{"start":26,"end":28,"cssClass":"pl-k"}],[],[{"start":0,"end":4,"cssClass":"pl-c1"},{"start":5,"end":32,"cssClass":"pl-s"},{"start":5,"end":6,"cssClass":"pl-pds"},{"start":31,"end":32,"cssClass":"pl-pds"}],[],[{"start":0,"end":2,"cssClass":"pl-k"},{"start":6,"end":20,"cssClass":"pl-s"},{"start":6,"end":7,"cssClass":"pl-pds"},{"start":7,"end":19,"cssClass":"pl-smi"},{"start":19,"end":20,"cssClass":"pl-pds"},{"start":21,"end":23,"cssClass":"pl-k"},{"start":24,"end":31,"cssClass":"pl-s"},{"start":24,"end":25,"cssClass":"pl-pds"},{"start":30,"end":31,"cssClass":"pl-pds"},{"start":34,"end":35,"cssClass":"pl-k"},{"start":36,"end":40,"cssClass":"pl-k"}],[{"start":2,"end":4,"cssClass":"pl-k"},{"start":8,"end":25,"cssClass":"pl-s"},{"start":8,"end":9,"cssClass":"pl-pds"},{"start":9,"end":24,"cssClass":"pl-smi"},{"start":24,"end":25,"cssClass":"pl-pds"},{"start":26,"end":28,"cssClass":"pl-k"},{"start":29,"end":36,"cssClass":"pl-s"},{"start":29,"end":30,"cssClass":"pl-pds"},{"start":35,"end":36,"cssClass":"pl-pds"},{"start":39,"end":40,"cssClass":"pl-k"},{"start":41,"end":45,"cssClass":"pl-k"}],[{"start":4,"end":27,"cssClass":"pl-c"},{"start":4,"end":5,"cssClass":"pl-c"}],[{"start":4,"end":8,"cssClass":"pl-c1"},{"start":9,"end":41,"cssClass":"pl-s"},{"start":9,"end":10,"cssClass":"pl-pds"},{"start":40,"end":41,"cssClass":"pl-pds"}],[{"start":4,"end":9,"cssClass":"pl-smi"},{"start":10,"end":32,"cssClass":"pl-s"},{"start":10,"end":11,"cssClass":"pl-pds"},{"start":11,"end":31,"cssClass":"pl-smi"},{"start":31,"end":32,"cssClass":"pl-pds"},{"start":33,"end":45,"cssClass":"pl-s"},{"start":33,"end":34,"cssClass":"pl-pds"},{"start":34,"end":44,"cssClass":"pl-smi"},{"start":44,"end":45,"cssClass":"pl-pds"}],[{"start":4,"end":30,"cssClass":"pl-c"},{"start":4,"end":5,"cssClass":"pl-c"}],[{"start":4,"end":9,"cssClass":"pl-smi"},{"start":10,"end":35,"cssClass":"pl-s"},{"start":10,"end":11,"cssClass":"pl-pds"},{"start":11,"end":34,"cssClass":"pl-smi"},{"start":34,"end":35,"cssClass":"pl-pds"},{"start":36,"end":48,"cssClass":"pl-s"},{"start":36,"end":37,"cssClass":"pl-pds"},{"start":37,"end":47,"cssClass":"pl-smi"},{"start":47,"end":48,"cssClass":"pl-pds"}],[{"start":4,"end":27,"cssClass":"pl-c"},{"start":4,"end":5,"cssClass":"pl-c"}],[{"start":4,"end":9,"cssClass":"pl-smi"},{"start":10,"end":32,"cssClass":"pl-s"},{"start":10,"end":11,"cssClass":"pl-pds"},{"start":11,"end":31,"cssClass":"pl-smi"},{"start":31,"end":32,"cssClass":"pl-pds"},{"start":33,"end":45,"cssClass":"pl-s"},{"start":33,"end":34,"cssClass":"pl-pds"},{"start":34,"end":44,"cssClass":"pl-smi"},{"start":44,"end":45,"cssClass":"pl-pds"}],[{"start":4,"end":22,"cssClass":"pl-c"},{"start":4,"end":5,"cssClass":"pl-c"}],[{"start":4,"end":9,"cssClass":"pl-smi"},{"start":10,"end":27,"cssClass":"pl-s"},{"start":10,"end":11,"cssClass":"pl-pds"},{"start":11,"end":26,"cssClass":"pl-smi"},{"start":26,"end":27,"cssClass":"pl-pds"},{"start":28,"end":40,"cssClass":"pl-s"},{"start":28,"end":29,"cssClass":"pl-pds"},{"start":29,"end":39,"cssClass":"pl-smi"},{"start":39,"end":40,"cssClass":"pl-pds"}],[{"start":4,"end":26,"cssClass":"pl-c"},{"start":4,"end":5,"cssClass":"pl-c"}],[{"start":4,"end":9,"cssClass":"pl-smi"},{"start":10,"end":27,"cssClass":"pl-s"},{"start":10,"end":11,"cssClass":"pl-pds"},{"start":11,"end":26,"cssClass":"pl-smi"},{"start":26,"end":27,"cssClass":"pl-pds"},{"start":28,"end":40,"cssClass":"pl-s"},{"start":28,"end":29,"cssClass":"pl-pds"},{"start":29,"end":39,"cssClass":"pl-smi"},{"start":39,"end":40,"cssClass":"pl-pds"}],[{"start":4,"end":28,"cssClass":"pl-c"},{"start":4,"end":5,"cssClass":"pl-c"}],[{"start":4,"end":9,"cssClass":"pl-smi"},{"start":10,"end":24,"cssClass":"pl-s"},{"start":10,"end":11,"cssClass":"pl-pds"},{"start":11,"end":23,"cssClass":"pl-smi"},{"start":23,"end":24,"cssClass":"pl-pds"},{"start":25,"end":37,"cssClass":"pl-s"},{"start":25,"end":26,"cssClass":"pl-pds"},{"start":26,"end":36,"cssClass":"pl-smi"},{"start":36,"end":37,"cssClass":"pl-pds"}],[],[{"start":4,"end":34,"cssClass":"pl-c"},{"start":4,"end":5,"cssClass":"pl-c"}],[{"start":4,"end":8,"cssClass":"pl-c1"},{"start":9,"end":44,"cssClass":"pl-s"},{"start":9,"end":10,"cssClass":"pl-pds"},{"start":43,"end":44,"cssClass":"pl-pds"}],[{"start":4,"end":9,"cssClass":"pl-smi"},{"start":10,"end":30,"cssClass":"pl-s"},{"start":10,"end":11,"cssClass":"pl-pds"},{"start":11,"end":29,"cssClass":"pl-smi"},{"start":29,"end":30,"cssClass":"pl-pds"},{"start":31,"end":43,"cssClass":"pl-s"},{"start":31,"end":32,"cssClass":"pl-pds"},{"start":32,"end":42,"cssClass":"pl-smi"},{"start":42,"end":43,"cssClass":"pl-pds"}],[{"start":4,"end":8,"cssClass":"pl-c1"},{"start":9,"end":26,"cssClass":"pl-s"},{"start":9,"end":10,"cssClass":"pl-pds"},{"start":10,"end":25,"cssClass":"pl-smi"},{"start":25,"end":26,"cssClass":"pl-pds"},{"start":27,"end":29,"cssClass":"pl-k"},{"start":30,"end":43,"cssClass":"pl-s"},{"start":30,"end":31,"cssClass":"pl-pds"},{"start":31,"end":42,"cssClass":"pl-smi"},{"start":42,"end":43,"cssClass":"pl-pds"}],[{"start":4,"end":8,"cssClass":"pl-c1"},{"start":9,"end":26,"cssClass":"pl-s"},{"start":9,"end":10,"cssClass":"pl-pds"},{"start":10,"end":25,"cssClass":"pl-smi"},{"start":25,"end":26,"cssClass":"pl-pds"},{"start":27,"end":29,"cssClass":"pl-k"},{"start":30,"end":43,"cssClass":"pl-s"},{"start":30,"end":31,"cssClass":"pl-pds"},{"start":31,"end":42,"cssClass":"pl-smi"},{"start":42,"end":43,"cssClass":"pl-pds"}],[{"start":4,"end":8,"cssClass":"pl-c1"},{"start":9,"end":28,"cssClass":"pl-s"},{"start":9,"end":10,"cssClass":"pl-pds"},{"start":10,"end":27,"cssClass":"pl-smi"},{"start":27,"end":28,"cssClass":"pl-pds"},{"start":29,"end":31,"cssClass":"pl-k"},{"start":32,"end":45,"cssClass":"pl-s"},{"start":32,"end":33,"cssClass":"pl-pds"},{"start":33,"end":44,"cssClass":"pl-smi"},{"start":44,"end":45,"cssClass":"pl-pds"}],[],[{"start":4,"end":28,"cssClass":"pl-c"},{"start":4,"end":5,"cssClass":"pl-c"}],[{"start":4,"end":8,"cssClass":"pl-c1"},{"start":9,"end":39,"cssClass":"pl-s"},{"start":9,"end":10,"cssClass":"pl-pds"},{"start":38,"end":39,"cssClass":"pl-pds"}],[{"start":4,"end":6,"cssClass":"pl-k"},{"start":10,"end":36,"cssClass":"pl-s"},{"start":10,"end":12,"cssClass":"pl-pds"},{"start":16,"end":35,"cssClass":"pl-s"},{"start":16,"end":17,"cssClass":"pl-pds"},{"start":17,"end":34,"cssClass":"pl-smi"},{"start":34,"end":35,"cssClass":"pl-pds"},{"start":35,"end":36,"cssClass":"pl-pds"},{"start":37,"end":40,"cssClass":"pl-k"},{"start":41,"end":60,"cssClass":"pl-s"},{"start":41,"end":43,"cssClass":"pl-pds"},{"start":47,"end":59,"cssClass":"pl-s"},{"start":47,"end":48,"cssClass":"pl-pds"},{"start":58,"end":59,"cssClass":"pl-pds"},{"start":59,"end":60,"cssClass":"pl-pds"},{"start":61,"end":63,"cssClass":"pl-k"},{"start":64,"end":90,"cssClass":"pl-s"},{"start":64,"end":66,"cssClass":"pl-pds"},{"start":70,"end":89,"cssClass":"pl-s"},{"start":70,"end":71,"cssClass":"pl-pds"},{"start":71,"end":88,"cssClass":"pl-smi"},{"start":88,"end":89,"cssClass":"pl-pds"},{"start":89,"end":90,"cssClass":"pl-pds"},{"start":91,"end":94,"cssClass":"pl-k"},{"start":95,"end":114,"cssClass":"pl-s"},{"start":95,"end":97,"cssClass":"pl-pds"},{"start":101,"end":113,"cssClass":"pl-s"},{"start":101,"end":102,"cssClass":"pl-pds"},{"start":112,"end":113,"cssClass":"pl-pds"},{"start":113,"end":114,"cssClass":"pl-pds"},{"start":117,"end":118,"cssClass":"pl-k"},{"start":119,"end":123,"cssClass":"pl-k"}],[{"start":6,"end":11,"cssClass":"pl-smi"},{"start":12,"end":30,"cssClass":"pl-s"},{"start":12,"end":13,"cssClass":"pl-pds"},{"start":13,"end":29,"cssClass":"pl-smi"},{"start":29,"end":30,"cssClass":"pl-pds"},{"start":31,"end":43,"cssClass":"pl-s"},{"start":31,"end":32,"cssClass":"pl-pds"},{"start":32,"end":42,"cssClass":"pl-smi"},{"start":42,"end":43,"cssClass":"pl-pds"}],[{"start":6,"end":11,"cssClass":"pl-smi"},{"start":12,"end":30,"cssClass":"pl-s"},{"start":12,"end":13,"cssClass":"pl-pds"},{"start":13,"end":29,"cssClass":"pl-smi"},{"start":29,"end":30,"cssClass":"pl-pds"},{"start":31,"end":43,"cssClass":"pl-s"},{"start":31,"end":32,"cssClass":"pl-pds"},{"start":32,"end":42,"cssClass":"pl-smi"},{"start":42,"end":43,"cssClass":"pl-pds"}],[{"start":6,"end":11,"cssClass":"pl-smi"},{"start":12,"end":30,"cssClass":"pl-s"},{"start":12,"end":13,"cssClass":"pl-pds"},{"start":13,"end":29,"cssClass":"pl-smi"},{"start":29,"end":30,"cssClass":"pl-pds"},{"start":31,"end":43,"cssClass":"pl-s"},{"start":31,"end":32,"cssClass":"pl-pds"},{"start":32,"end":42,"cssClass":"pl-smi"},{"start":42,"end":43,"cssClass":"pl-pds"}],[{"start":4,"end":8,"cssClass":"pl-k"},{"start":12,"end":38,"cssClass":"pl-s"},{"start":12,"end":14,"cssClass":"pl-pds"},{"start":18,"end":37,"cssClass":"pl-s"},{"start":18,"end":19,"cssClass":"pl-pds"},{"start":19,"end":36,"cssClass":"pl-smi"},{"start":36,"end":37,"cssClass":"pl-pds"},{"start":37,"end":38,"cssClass":"pl-pds"},{"start":39,"end":42,"cssClass":"pl-k"},{"start":43,"end":62,"cssClass":"pl-s"},{"start":43,"end":45,"cssClass":"pl-pds"},{"start":49,"end":61,"cssClass":"pl-s"},{"start":49,"end":50,"cssClass":"pl-pds"},{"start":60,"end":61,"cssClass":"pl-pds"},{"start":61,"end":62,"cssClass":"pl-pds"},{"start":63,"end":65,"cssClass":"pl-k"},{"start":66,"end":92,"cssClass":"pl-s"},{"start":66,"end":68,"cssClass":"pl-pds"},{"start":72,"end":91,"cssClass":"pl-s"},{"start":72,"end":73,"cssClass":"pl-pds"},{"start":73,"end":90,"cssClass":"pl-smi"},{"start":90,"end":91,"cssClass":"pl-pds"},{"start":91,"end":92,"cssClass":"pl-pds"},{"start":93,"end":96,"cssClass":"pl-k"},{"start":97,"end":116,"cssClass":"pl-s"},{"start":97,"end":99,"cssClass":"pl-pds"},{"start":103,"end":115,"cssClass":"pl-s"},{"start":103,"end":104,"cssClass":"pl-pds"},{"start":114,"end":115,"cssClass":"pl-pds"},{"start":115,"end":116,"cssClass":"pl-pds"},{"start":119,"end":120,"cssClass":"pl-k"},{"start":121,"end":125,"cssClass":"pl-k"}],[{"start":6,"end":11,"cssClass":"pl-smi"},{"start":12,"end":34,"cssClass":"pl-s"},{"start":12,"end":13,"cssClass":"pl-pds"},{"start":13,"end":33,"cssClass":"pl-smi"},{"start":33,"end":34,"cssClass":"pl-pds"},{"start":35,"end":47,"cssClass":"pl-s"},{"start":35,"end":36,"cssClass":"pl-pds"},{"start":36,"end":46,"cssClass":"pl-smi"},{"start":46,"end":47,"cssClass":"pl-pds"}],[{"start":6,"end":11,"cssClass":"pl-smi"},{"start":12,"end":28,"cssClass":"pl-s"},{"start":12,"end":13,"cssClass":"pl-pds"},{"start":13,"end":27,"cssClass":"pl-smi"},{"start":27,"end":28,"cssClass":"pl-pds"},{"start":29,"end":41,"cssClass":"pl-s"},{"start":29,"end":30,"cssClass":"pl-pds"},{"start":30,"end":40,"cssClass":"pl-smi"},{"start":40,"end":41,"cssClass":"pl-pds"}],[{"start":4,"end":8,"cssClass":"pl-k"},{"start":12,"end":38,"cssClass":"pl-s"},{"start":12,"end":14,"cssClass":"pl-pds"},{"start":18,"end":37,"cssClass":"pl-s"},{"start":18,"end":19,"cssClass":"pl-pds"},{"start":19,"end":36,"cssClass":"pl-smi"},{"start":36,"end":37,"cssClass":"pl-pds"},{"start":37,"end":38,"cssClass":"pl-pds"},{"start":39,"end":42,"cssClass":"pl-k"},{"start":43,"end":62,"cssClass":"pl-s"},{"start":43,"end":45,"cssClass":"pl-pds"},{"start":49,"end":61,"cssClass":"pl-s"},{"start":49,"end":50,"cssClass":"pl-pds"},{"start":60,"end":61,"cssClass":"pl-pds"},{"start":61,"end":62,"cssClass":"pl-pds"},{"start":65,"end":66,"cssClass":"pl-k"},{"start":67,"end":71,"cssClass":"pl-k"}],[{"start":6,"end":11,"cssClass":"pl-smi"},{"start":12,"end":28,"cssClass":"pl-s"},{"start":12,"end":13,"cssClass":"pl-pds"},{"start":13,"end":27,"cssClass":"pl-smi"},{"start":27,"end":28,"cssClass":"pl-pds"},{"start":29,"end":41,"cssClass":"pl-s"},{"start":29,"end":30,"cssClass":"pl-pds"},{"start":30,"end":40,"cssClass":"pl-smi"},{"start":40,"end":41,"cssClass":"pl-pds"},{"start":41,"end":42,"cssClass":"pl-k"},{"start":43,"end":45,"cssClass":"pl-k"}],[{"start":2,"end":6,"cssClass":"pl-k"}],[{"start":4,"end":8,"cssClass":"pl-c1"},{"start":9,"end":49,"cssClass":"pl-s"},{"start":9,"end":10,"cssClass":"pl-pds"},{"start":48,"end":49,"cssClass":"pl-pds"},{"start":49,"end":50,"cssClass":"pl-k"},{"start":51,"end":53,"cssClass":"pl-k"},{"start":53,"end":54,"cssClass":"pl-k"},{"start":55,"end":57,"cssClass":"pl-k"}],[],[{"start":0,"end":22,"cssClass":"pl-c"},{"start":0,"end":1,"cssClass":"pl-c"}],[{"start":0,"end":2,"cssClass":"pl-k"},{"start":6,"end":20,"cssClass":"pl-s"},{"start":6,"end":7,"cssClass":"pl-pds"},{"start":7,"end":19,"cssClass":"pl-smi"},{"start":19,"end":20,"cssClass":"pl-pds"},{"start":21,"end":23,"cssClass":"pl-k"},{"start":24,"end":31,"cssClass":"pl-s"},{"start":24,"end":25,"cssClass":"pl-pds"},{"start":30,"end":31,"cssClass":"pl-pds"},{"start":34,"end":35,"cssClass":"pl-k"},{"start":36,"end":40,"cssClass":"pl-k"}],[{"start":2,"end":4,"cssClass":"pl-k"},{"start":8,"end":30,"cssClass":"pl-s"},{"start":8,"end":9,"cssClass":"pl-pds"},{"start":9,"end":29,"cssClass":"pl-smi"},{"start":29,"end":30,"cssClass":"pl-pds"},{"start":31,"end":33,"cssClass":"pl-k"},{"start":34,"end":40,"cssClass":"pl-s"},{"start":34,"end":35,"cssClass":"pl-pds"},{"start":39,"end":40,"cssClass":"pl-pds"},{"start":43,"end":44,"cssClass":"pl-k"},{"start":45,"end":49,"cssClass":"pl-k"}],[{"start":4,"end":8,"cssClass":"pl-c1"},{"start":9,"end":42,"cssClass":"pl-s"},{"start":9,"end":10,"cssClass":"pl-pds"},{"start":41,"end":42,"cssClass":"pl-pds"}],[{"start":4,"end":6,"cssClass":"pl-k"},{"start":10,"end":36,"cssClass":"pl-s"},{"start":10,"end":12,"cssClass":"pl-pds"},{"start":16,"end":35,"cssClass":"pl-s"},{"start":16,"end":17,"cssClass":"pl-pds"},{"start":17,"end":34,"cssClass":"pl-smi"},{"start":34,"end":35,"cssClass":"pl-pds"},{"start":35,"end":36,"cssClass":"pl-pds"},{"start":37,"end":40,"cssClass":"pl-k"},{"start":41,"end":60,"cssClass":"pl-s"},{"start":41,"end":43,"cssClass":"pl-pds"},{"start":47,"end":59,"cssClass":"pl-s"},{"start":47,"end":48,"cssClass":"pl-pds"},{"start":58,"end":59,"cssClass":"pl-pds"},{"start":59,"end":60,"cssClass":"pl-pds"},{"start":63,"end":64,"cssClass":"pl-k"},{"start":65,"end":69,"cssClass":"pl-k"},{"start":70,"end":75,"cssClass":"pl-smi"},{"start":76,"end":100,"cssClass":"pl-s"},{"start":76,"end":77,"cssClass":"pl-pds"},{"start":77,"end":99,"cssClass":"pl-smi"},{"start":99,"end":100,"cssClass":"pl-pds"},{"start":101,"end":113,"cssClass":"pl-s"},{"start":101,"end":102,"cssClass":"pl-pds"},{"start":102,"end":112,"cssClass":"pl-smi"},{"start":112,"end":113,"cssClass":"pl-pds"},{"start":113,"end":114,"cssClass":"pl-k"},{"start":115,"end":117,"cssClass":"pl-k"}],[{"start":4,"end":6,"cssClass":"pl-k"},{"start":10,"end":36,"cssClass":"pl-s"},{"start":10,"end":12,"cssClass":"pl-pds"},{"start":16,"end":35,"cssClass":"pl-s"},{"start":16,"end":17,"cssClass":"pl-pds"},{"start":17,"end":34,"cssClass":"pl-smi"},{"start":34,"end":35,"cssClass":"pl-pds"},{"start":35,"end":36,"cssClass":"pl-pds"},{"start":37,"end":40,"cssClass":"pl-k"},{"start":41,"end":60,"cssClass":"pl-s"},{"start":41,"end":43,"cssClass":"pl-pds"},{"start":47,"end":59,"cssClass":"pl-s"},{"start":47,"end":48,"cssClass":"pl-pds"},{"start":58,"end":59,"cssClass":"pl-pds"},{"start":59,"end":60,"cssClass":"pl-pds"},{"start":63,"end":64,"cssClass":"pl-k"},{"start":65,"end":69,"cssClass":"pl-k"},{"start":70,"end":75,"cssClass":"pl-smi"},{"start":76,"end":97,"cssClass":"pl-s"},{"start":76,"end":77,"cssClass":"pl-pds"},{"start":77,"end":96,"cssClass":"pl-smi"},{"start":96,"end":97,"cssClass":"pl-pds"},{"start":98,"end":110,"cssClass":"pl-s"},{"start":98,"end":99,"cssClass":"pl-pds"},{"start":99,"end":109,"cssClass":"pl-smi"},{"start":109,"end":110,"cssClass":"pl-pds"},{"start":110,"end":111,"cssClass":"pl-k"},{"start":112,"end":114,"cssClass":"pl-k"}],[{"start":4,"end":6,"cssClass":"pl-k"},{"start":10,"end":36,"cssClass":"pl-s"},{"start":10,"end":12,"cssClass":"pl-pds"},{"start":16,"end":35,"cssClass":"pl-s"},{"start":16,"end":17,"cssClass":"pl-pds"},{"start":17,"end":34,"cssClass":"pl-smi"},{"start":34,"end":35,"cssClass":"pl-pds"},{"start":35,"end":36,"cssClass":"pl-pds"},{"start":37,"end":40,"cssClass":"pl-k"},{"start":41,"end":60,"cssClass":"pl-s"},{"start":41,"end":43,"cssClass":"pl-pds"},{"start":47,"end":59,"cssClass":"pl-s"},{"start":47,"end":48,"cssClass":"pl-pds"},{"start":58,"end":59,"cssClass":"pl-pds"},{"start":59,"end":60,"cssClass":"pl-pds"},{"start":63,"end":64,"cssClass":"pl-k"},{"start":65,"end":69,"cssClass":"pl-k"},{"start":70,"end":75,"cssClass":"pl-smi"},{"start":76,"end":96,"cssClass":"pl-s"},{"start":76,"end":77,"cssClass":"pl-pds"},{"start":77,"end":95,"cssClass":"pl-smi"},{"start":95,"end":96,"cssClass":"pl-pds"},{"start":97,"end":109,"cssClass":"pl-s"},{"start":97,"end":98,"cssClass":"pl-pds"},{"start":98,"end":108,"cssClass":"pl-smi"},{"start":108,"end":109,"cssClass":"pl-pds"},{"start":109,"end":110,"cssClass":"pl-k"},{"start":111,"end":113,"cssClass":"pl-k"}],[{"start":4,"end":6,"cssClass":"pl-k"},{"start":10,"end":36,"cssClass":"pl-s"},{"start":10,"end":12,"cssClass":"pl-pds"},{"start":16,"end":35,"cssClass":"pl-s"},{"start":16,"end":17,"cssClass":"pl-pds"},{"start":17,"end":34,"cssClass":"pl-smi"},{"start":34,"end":35,"cssClass":"pl-pds"},{"start":35,"end":36,"cssClass":"pl-pds"},{"start":37,"end":40,"cssClass":"pl-k"},{"start":41,"end":60,"cssClass":"pl-s"},{"start":41,"end":43,"cssClass":"pl-pds"},{"start":47,"end":59,"cssClass":"pl-s"},{"start":47,"end":48,"cssClass":"pl-pds"},{"start":58,"end":59,"cssClass":"pl-pds"},{"start":59,"end":60,"cssClass":"pl-pds"},{"start":63,"end":64,"cssClass":"pl-k"},{"start":65,"end":69,"cssClass":"pl-k"},{"start":70,"end":75,"cssClass":"pl-smi"},{"start":76,"end":99,"cssClass":"pl-s"},{"start":76,"end":77,"cssClass":"pl-pds"},{"start":77,"end":98,"cssClass":"pl-smi"},{"start":98,"end":99,"cssClass":"pl-pds"},{"start":100,"end":112,"cssClass":"pl-s"},{"start":100,"end":101,"cssClass":"pl-pds"},{"start":101,"end":111,"cssClass":"pl-smi"},{"start":111,"end":112,"cssClass":"pl-pds"},{"start":112,"end":113,"cssClass":"pl-k"},{"start":114,"end":116,"cssClass":"pl-k"}],[{"start":4,"end":6,"cssClass":"pl-k"},{"start":10,"end":36,"cssClass":"pl-s"},{"start":10,"end":12,"cssClass":"pl-pds"},{"start":16,"end":35,"cssClass":"pl-s"},{"start":16,"end":17,"cssClass":"pl-pds"},{"start":17,"end":34,"cssClass":"pl-smi"},{"start":34,"end":35,"cssClass":"pl-pds"},{"start":35,"end":36,"cssClass":"pl-pds"},{"start":37,"end":40,"cssClass":"pl-k"},{"start":41,"end":60,"cssClass":"pl-s"},{"start":41,"end":43,"cssClass":"pl-pds"},{"start":47,"end":59,"cssClass":"pl-s"},{"start":47,"end":48,"cssClass":"pl-pds"},{"start":58,"end":59,"cssClass":"pl-pds"},{"start":59,"end":60,"cssClass":"pl-pds"},{"start":63,"end":64,"cssClass":"pl-k"},{"start":65,"end":69,"cssClass":"pl-k"},{"start":70,"end":75,"cssClass":"pl-smi"},{"start":76,"end":97,"cssClass":"pl-s"},{"start":76,"end":77,"cssClass":"pl-pds"},{"start":77,"end":96,"cssClass":"pl-smi"},{"start":96,"end":97,"cssClass":"pl-pds"},{"start":98,"end":110,"cssClass":"pl-s"},{"start":98,"end":99,"cssClass":"pl-pds"},{"start":99,"end":109,"cssClass":"pl-smi"},{"start":109,"end":110,"cssClass":"pl-pds"},{"start":110,"end":111,"cssClass":"pl-k"},{"start":112,"end":114,"cssClass":"pl-k"}],[{"start":4,"end":6,"cssClass":"pl-k"},{"start":10,"end":36,"cssClass":"pl-s"},{"start":10,"end":12,"cssClass":"pl-pds"},{"start":16,"end":35,"cssClass":"pl-s"},{"start":16,"end":17,"cssClass":"pl-pds"},{"start":17,"end":34,"cssClass":"pl-smi"},{"start":34,"end":35,"cssClass":"pl-pds"},{"start":35,"end":36,"cssClass":"pl-pds"},{"start":37,"end":40,"cssClass":"pl-k"},{"start":41,"end":60,"cssClass":"pl-s"},{"start":41,"end":43,"cssClass":"pl-pds"},{"start":47,"end":59,"cssClass":"pl-s"},{"start":47,"end":48,"cssClass":"pl-pds"},{"start":58,"end":59,"cssClass":"pl-pds"},{"start":59,"end":60,"cssClass":"pl-pds"},{"start":61,"end":63,"cssClass":"pl-k"},{"start":64,"end":90,"cssClass":"pl-s"},{"start":64,"end":66,"cssClass":"pl-pds"},{"start":70,"end":89,"cssClass":"pl-s"},{"start":70,"end":71,"cssClass":"pl-pds"},{"start":71,"end":88,"cssClass":"pl-smi"},{"start":88,"end":89,"cssClass":"pl-pds"},{"start":89,"end":90,"cssClass":"pl-pds"},{"start":91,"end":94,"cssClass":"pl-k"},{"start":95,"end":114,"cssClass":"pl-s"},{"start":95,"end":97,"cssClass":"pl-pds"},{"start":101,"end":113,"cssClass":"pl-s"},{"start":101,"end":102,"cssClass":"pl-pds"},{"start":112,"end":113,"cssClass":"pl-pds"},{"start":113,"end":114,"cssClass":"pl-pds"},{"start":117,"end":118,"cssClass":"pl-k"},{"start":119,"end":123,"cssClass":"pl-k"},{"start":124,"end":129,"cssClass":"pl-smi"},{"start":130,"end":157,"cssClass":"pl-s"},{"start":130,"end":131,"cssClass":"pl-pds"},{"start":131,"end":156,"cssClass":"pl-smi"},{"start":156,"end":157,"cssClass":"pl-pds"},{"start":158,"end":170,"cssClass":"pl-s"},{"start":158,"end":159,"cssClass":"pl-pds"},{"start":159,"end":169,"cssClass":"pl-smi"},{"start":169,"end":170,"cssClass":"pl-pds"},{"start":170,"end":171,"cssClass":"pl-k"},{"start":172,"end":174,"cssClass":"pl-k"}],[{"start":4,"end":6,"cssClass":"pl-k"},{"start":10,"end":36,"cssClass":"pl-s"},{"start":10,"end":12,"cssClass":"pl-pds"},{"start":16,"end":35,"cssClass":"pl-s"},{"start":16,"end":17,"cssClass":"pl-pds"},{"start":17,"end":34,"cssClass":"pl-smi"},{"start":34,"end":35,"cssClass":"pl-pds"},{"start":35,"end":36,"cssClass":"pl-pds"},{"start":37,"end":40,"cssClass":"pl-k"},{"start":41,"end":60,"cssClass":"pl-s"},{"start":41,"end":43,"cssClass":"pl-pds"},{"start":47,"end":59,"cssClass":"pl-s"},{"start":47,"end":48,"cssClass":"pl-pds"},{"start":58,"end":59,"cssClass":"pl-pds"},{"start":59,"end":60,"cssClass":"pl-pds"},{"start":63,"end":64,"cssClass":"pl-k"},{"start":65,"end":69,"cssClass":"pl-k"},{"start":70,"end":75,"cssClass":"pl-smi"},{"start":76,"end":105,"cssClass":"pl-s"},{"start":76,"end":77,"cssClass":"pl-pds"},{"start":77,"end":104,"cssClass":"pl-smi"},{"start":104,"end":105,"cssClass":"pl-pds"},{"start":106,"end":118,"cssClass":"pl-s"},{"start":106,"end":107,"cssClass":"pl-pds"},{"start":107,"end":117,"cssClass":"pl-smi"},{"start":117,"end":118,"cssClass":"pl-pds"},{"start":118,"end":119,"cssClass":"pl-k"},{"start":120,"end":122,"cssClass":"pl-k"}],[{"start":4,"end":6,"cssClass":"pl-k"},{"start":10,"end":36,"cssClass":"pl-s"},{"start":10,"end":12,"cssClass":"pl-pds"},{"start":16,"end":35,"cssClass":"pl-s"},{"start":16,"end":17,"cssClass":"pl-pds"},{"start":17,"end":34,"cssClass":"pl-smi"},{"start":34,"end":35,"cssClass":"pl-pds"},{"start":35,"end":36,"cssClass":"pl-pds"},{"start":37,"end":40,"cssClass":"pl-k"},{"start":41,"end":60,"cssClass":"pl-s"},{"start":41,"end":43,"cssClass":"pl-pds"},{"start":47,"end":59,"cssClass":"pl-s"},{"start":47,"end":48,"cssClass":"pl-pds"},{"start":58,"end":59,"cssClass":"pl-pds"},{"start":59,"end":60,"cssClass":"pl-pds"},{"start":63,"end":64,"cssClass":"pl-k"},{"start":65,"end":69,"cssClass":"pl-k"},{"start":70,"end":75,"cssClass":"pl-smi"},{"start":76,"end":100,"cssClass":"pl-s"},{"start":76,"end":77,"cssClass":"pl-pds"},{"start":77,"end":99,"cssClass":"pl-smi"},{"start":99,"end":100,"cssClass":"pl-pds"},{"start":101,"end":113,"cssClass":"pl-s"},{"start":101,"end":102,"cssClass":"pl-pds"},{"start":102,"end":112,"cssClass":"pl-smi"},{"start":112,"end":113,"cssClass":"pl-pds"},{"start":113,"end":114,"cssClass":"pl-k"},{"start":115,"end":117,"cssClass":"pl-k"}],[{"start":4,"end":6,"cssClass":"pl-k"},{"start":10,"end":36,"cssClass":"pl-s"},{"start":10,"end":12,"cssClass":"pl-pds"},{"start":16,"end":35,"cssClass":"pl-s"},{"start":16,"end":17,"cssClass":"pl-pds"},{"start":17,"end":34,"cssClass":"pl-smi"},{"start":34,"end":35,"cssClass":"pl-pds"},{"start":35,"end":36,"cssClass":"pl-pds"},{"start":37,"end":40,"cssClass":"pl-k"},{"start":41,"end":60,"cssClass":"pl-s"},{"start":41,"end":43,"cssClass":"pl-pds"},{"start":47,"end":59,"cssClass":"pl-s"},{"start":47,"end":48,"cssClass":"pl-pds"},{"start":58,"end":59,"cssClass":"pl-pds"},{"start":59,"end":60,"cssClass":"pl-pds"},{"start":63,"end":64,"cssClass":"pl-k"},{"start":65,"end":69,"cssClass":"pl-k"},{"start":70,"end":75,"cssClass":"pl-smi"},{"start":76,"end":104,"cssClass":"pl-s"},{"start":76,"end":77,"cssClass":"pl-pds"},{"start":77,"end":103,"cssClass":"pl-smi"},{"start":103,"end":104,"cssClass":"pl-pds"},{"start":105,"end":117,"cssClass":"pl-s"},{"start":105,"end":106,"cssClass":"pl-pds"},{"start":106,"end":116,"cssClass":"pl-smi"},{"start":116,"end":117,"cssClass":"pl-pds"},{"start":117,"end":118,"cssClass":"pl-k"},{"start":119,"end":121,"cssClass":"pl-k"}],[{"start":4,"end":6,"cssClass":"pl-k"},{"start":10,"end":36,"cssClass":"pl-s"},{"start":10,"end":12,"cssClass":"pl-pds"},{"start":16,"end":35,"cssClass":"pl-s"},{"start":16,"end":17,"cssClass":"pl-pds"},{"start":17,"end":34,"cssClass":"pl-smi"},{"start":34,"end":35,"cssClass":"pl-pds"},{"start":35,"end":36,"cssClass":"pl-pds"},{"start":37,"end":40,"cssClass":"pl-k"},{"start":41,"end":60,"cssClass":"pl-s"},{"start":41,"end":43,"cssClass":"pl-pds"},{"start":47,"end":59,"cssClass":"pl-s"},{"start":47,"end":48,"cssClass":"pl-pds"},{"start":58,"end":59,"cssClass":"pl-pds"},{"start":59,"end":60,"cssClass":"pl-pds"},{"start":63,"end":64,"cssClass":"pl-k"},{"start":65,"end":69,"cssClass":"pl-k"},{"start":70,"end":75,"cssClass":"pl-smi"},{"start":76,"end":101,"cssClass":"pl-s"},{"start":76,"end":77,"cssClass":"pl-pds"},{"start":77,"end":100,"cssClass":"pl-smi"},{"start":100,"end":101,"cssClass":"pl-pds"},{"start":102,"end":114,"cssClass":"pl-s"},{"start":102,"end":103,"cssClass":"pl-pds"},{"start":103,"end":113,"cssClass":"pl-smi"},{"start":113,"end":114,"cssClass":"pl-pds"},{"start":114,"end":115,"cssClass":"pl-k"},{"start":116,"end":118,"cssClass":"pl-k"}],[{"start":4,"end":6,"cssClass":"pl-k"},{"start":10,"end":36,"cssClass":"pl-s"},{"start":10,"end":12,"cssClass":"pl-pds"},{"start":16,"end":35,"cssClass":"pl-s"},{"start":16,"end":17,"cssClass":"pl-pds"},{"start":17,"end":34,"cssClass":"pl-smi"},{"start":34,"end":35,"cssClass":"pl-pds"},{"start":35,"end":36,"cssClass":"pl-pds"},{"start":37,"end":40,"cssClass":"pl-k"},{"start":41,"end":60,"cssClass":"pl-s"},{"start":41,"end":43,"cssClass":"pl-pds"},{"start":47,"end":59,"cssClass":"pl-s"},{"start":47,"end":48,"cssClass":"pl-pds"},{"start":58,"end":59,"cssClass":"pl-pds"},{"start":59,"end":60,"cssClass":"pl-pds"},{"start":63,"end":64,"cssClass":"pl-k"},{"start":65,"end":69,"cssClass":"pl-k"},{"start":70,"end":75,"cssClass":"pl-smi"},{"start":76,"end":97,"cssClass":"pl-s"},{"start":76,"end":77,"cssClass":"pl-pds"},{"start":77,"end":96,"cssClass":"pl-smi"},{"start":96,"end":97,"cssClass":"pl-pds"},{"start":98,"end":110,"cssClass":"pl-s"},{"start":98,"end":99,"cssClass":"pl-pds"},{"start":99,"end":109,"cssClass":"pl-smi"},{"start":109,"end":110,"cssClass":"pl-pds"},{"start":110,"end":111,"cssClass":"pl-k"},{"start":112,"end":114,"cssClass":"pl-k"}],[{"start":4,"end":6,"cssClass":"pl-k"},{"start":10,"end":36,"cssClass":"pl-s"},{"start":10,"end":12,"cssClass":"pl-pds"},{"start":16,"end":35,"cssClass":"pl-s"},{"start":16,"end":17,"cssClass":"pl-pds"},{"start":17,"end":34,"cssClass":"pl-smi"},{"start":34,"end":35,"cssClass":"pl-pds"},{"start":35,"end":36,"cssClass":"pl-pds"},{"start":37,"end":40,"cssClass":"pl-k"},{"start":41,"end":59,"cssClass":"pl-s"},{"start":41,"end":43,"cssClass":"pl-pds"},{"start":47,"end":58,"cssClass":"pl-s"},{"start":47,"end":48,"cssClass":"pl-pds"},{"start":57,"end":58,"cssClass":"pl-pds"},{"start":58,"end":59,"cssClass":"pl-pds"},{"start":62,"end":63,"cssClass":"pl-k"},{"start":64,"end":68,"cssClass":"pl-k"},{"start":69,"end":74,"cssClass":"pl-smi"},{"start":75,"end":107,"cssClass":"pl-s"},{"start":75,"end":76,"cssClass":"pl-pds"},{"start":76,"end":106,"cssClass":"pl-smi"},{"start":106,"end":107,"cssClass":"pl-pds"},{"start":108,"end":120,"cssClass":"pl-s"},{"start":108,"end":109,"cssClass":"pl-pds"},{"start":109,"end":119,"cssClass":"pl-smi"},{"start":119,"end":120,"cssClass":"pl-pds"},{"start":120,"end":121,"cssClass":"pl-k"},{"start":122,"end":124,"cssClass":"pl-k"}],[{"start":4,"end":6,"cssClass":"pl-k"},{"start":10,"end":36,"cssClass":"pl-s"},{"start":10,"end":12,"cssClass":"pl-pds"},{"start":16,"end":35,"cssClass":"pl-s"},{"start":16,"end":17,"cssClass":"pl-pds"},{"start":17,"end":34,"cssClass":"pl-smi"},{"start":34,"end":35,"cssClass":"pl-pds"},{"start":35,"end":36,"cssClass":"pl-pds"},{"start":37,"end":40,"cssClass":"pl-k"},{"start":41,"end":60,"cssClass":"pl-s"},{"start":41,"end":43,"cssClass":"pl-pds"},{"start":47,"end":59,"cssClass":"pl-s"},{"start":47,"end":48,"cssClass":"pl-pds"},{"start":58,"end":59,"cssClass":"pl-pds"},{"start":59,"end":60,"cssClass":"pl-pds"},{"start":63,"end":64,"cssClass":"pl-k"},{"start":65,"end":69,"cssClass":"pl-k"},{"start":70,"end":75,"cssClass":"pl-smi"},{"start":76,"end":102,"cssClass":"pl-s"},{"start":76,"end":77,"cssClass":"pl-pds"},{"start":77,"end":101,"cssClass":"pl-smi"},{"start":101,"end":102,"cssClass":"pl-pds"},{"start":103,"end":115,"cssClass":"pl-s"},{"start":103,"end":104,"cssClass":"pl-pds"},{"start":104,"end":114,"cssClass":"pl-smi"},{"start":114,"end":115,"cssClass":"pl-pds"},{"start":115,"end":116,"cssClass":"pl-k"},{"start":117,"end":119,"cssClass":"pl-k"}],[{"start":4,"end":6,"cssClass":"pl-k"},{"start":10,"end":36,"cssClass":"pl-s"},{"start":10,"end":12,"cssClass":"pl-pds"},{"start":16,"end":35,"cssClass":"pl-s"},{"start":16,"end":17,"cssClass":"pl-pds"},{"start":17,"end":34,"cssClass":"pl-smi"},{"start":34,"end":35,"cssClass":"pl-pds"},{"start":35,"end":36,"cssClass":"pl-pds"},{"start":37,"end":40,"cssClass":"pl-k"},{"start":41,"end":60,"cssClass":"pl-s"},{"start":41,"end":43,"cssClass":"pl-pds"},{"start":47,"end":59,"cssClass":"pl-s"},{"start":47,"end":48,"cssClass":"pl-pds"},{"start":58,"end":59,"cssClass":"pl-pds"},{"start":59,"end":60,"cssClass":"pl-pds"},{"start":63,"end":64,"cssClass":"pl-k"},{"start":65,"end":69,"cssClass":"pl-k"},{"start":70,"end":75,"cssClass":"pl-smi"},{"start":76,"end":98,"cssClass":"pl-s"},{"start":76,"end":77,"cssClass":"pl-pds"},{"start":77,"end":97,"cssClass":"pl-smi"},{"start":97,"end":98,"cssClass":"pl-pds"},{"start":99,"end":111,"cssClass":"pl-s"},{"start":99,"end":100,"cssClass":"pl-pds"},{"start":100,"end":110,"cssClass":"pl-smi"},{"start":110,"end":111,"cssClass":"pl-pds"},{"start":111,"end":112,"cssClass":"pl-k"},{"start":113,"end":115,"cssClass":"pl-k"}],[{"start":4,"end":6,"cssClass":"pl-k"},{"start":10,"end":36,"cssClass":"pl-s"},{"start":10,"end":12,"cssClass":"pl-pds"},{"start":16,"end":35,"cssClass":"pl-s"},{"start":16,"end":17,"cssClass":"pl-pds"},{"start":17,"end":34,"cssClass":"pl-smi"},{"start":34,"end":35,"cssClass":"pl-pds"},{"start":35,"end":36,"cssClass":"pl-pds"},{"start":37,"end":40,"cssClass":"pl-k"},{"start":41,"end":60,"cssClass":"pl-s"},{"start":41,"end":43,"cssClass":"pl-pds"},{"start":47,"end":59,"cssClass":"pl-s"},{"start":47,"end":48,"cssClass":"pl-pds"},{"start":58,"end":59,"cssClass":"pl-pds"},{"start":59,"end":60,"cssClass":"pl-pds"},{"start":63,"end":64,"cssClass":"pl-k"},{"start":65,"end":69,"cssClass":"pl-k"},{"start":70,"end":75,"cssClass":"pl-smi"},{"start":76,"end":99,"cssClass":"pl-s"},{"start":76,"end":77,"cssClass":"pl-pds"},{"start":77,"end":98,"cssClass":"pl-smi"},{"start":98,"end":99,"cssClass":"pl-pds"},{"start":100,"end":112,"cssClass":"pl-s"},{"start":100,"end":101,"cssClass":"pl-pds"},{"start":101,"end":111,"cssClass":"pl-smi"},{"start":111,"end":112,"cssClass":"pl-pds"},{"start":112,"end":113,"cssClass":"pl-k"},{"start":114,"end":116,"cssClass":"pl-k"}],[{"start":4,"end":6,"cssClass":"pl-k"},{"start":10,"end":36,"cssClass":"pl-s"},{"start":10,"end":12,"cssClass":"pl-pds"},{"start":16,"end":35,"cssClass":"pl-s"},{"start":16,"end":17,"cssClass":"pl-pds"},{"start":17,"end":34,"cssClass":"pl-smi"},{"start":34,"end":35,"cssClass":"pl-pds"},{"start":35,"end":36,"cssClass":"pl-pds"},{"start":37,"end":40,"cssClass":"pl-k"},{"start":41,"end":60,"cssClass":"pl-s"},{"start":41,"end":43,"cssClass":"pl-pds"},{"start":47,"end":59,"cssClass":"pl-s"},{"start":47,"end":48,"cssClass":"pl-pds"},{"start":58,"end":59,"cssClass":"pl-pds"},{"start":59,"end":60,"cssClass":"pl-pds"},{"start":61,"end":63,"cssClass":"pl-k"},{"start":64,"end":90,"cssClass":"pl-s"},{"start":64,"end":66,"cssClass":"pl-pds"},{"start":70,"end":89,"cssClass":"pl-s"},{"start":70,"end":71,"cssClass":"pl-pds"},{"start":71,"end":88,"cssClass":"pl-smi"},{"start":88,"end":89,"cssClass":"pl-pds"},{"start":89,"end":90,"cssClass":"pl-pds"},{"start":91,"end":94,"cssClass":"pl-k"},{"start":95,"end":114,"cssClass":"pl-s"},{"start":95,"end":97,"cssClass":"pl-pds"},{"start":101,"end":113,"cssClass":"pl-s"},{"start":101,"end":102,"cssClass":"pl-pds"},{"start":112,"end":113,"cssClass":"pl-pds"},{"start":113,"end":114,"cssClass":"pl-pds"},{"start":117,"end":118,"cssClass":"pl-k"},{"start":119,"end":123,"cssClass":"pl-k"},{"start":124,"end":129,"cssClass":"pl-smi"},{"start":130,"end":154,"cssClass":"pl-s"},{"start":130,"end":131,"cssClass":"pl-pds"},{"start":131,"end":153,"cssClass":"pl-smi"},{"start":153,"end":154,"cssClass":"pl-pds"},{"start":155,"end":167,"cssClass":"pl-s"},{"start":155,"end":156,"cssClass":"pl-pds"},{"start":156,"end":166,"cssClass":"pl-smi"},{"start":166,"end":167,"cssClass":"pl-pds"},{"start":167,"end":168,"cssClass":"pl-k"},{"start":169,"end":171,"cssClass":"pl-k"}],[{"start":4,"end":6,"cssClass":"pl-k"},{"start":10,"end":36,"cssClass":"pl-s"},{"start":10,"end":12,"cssClass":"pl-pds"},{"start":16,"end":35,"cssClass":"pl-s"},{"start":16,"end":17,"cssClass":"pl-pds"},{"start":17,"end":34,"cssClass":"pl-smi"},{"start":34,"end":35,"cssClass":"pl-pds"},{"start":35,"end":36,"cssClass":"pl-pds"},{"start":37,"end":40,"cssClass":"pl-k"},{"start":41,"end":60,"cssClass":"pl-s"},{"start":41,"end":43,"cssClass":"pl-pds"},{"start":47,"end":59,"cssClass":"pl-s"},{"start":47,"end":48,"cssClass":"pl-pds"},{"start":58,"end":59,"cssClass":"pl-pds"},{"start":59,"end":60,"cssClass":"pl-pds"},{"start":63,"end":64,"cssClass":"pl-k"},{"start":65,"end":69,"cssClass":"pl-k"},{"start":70,"end":75,"cssClass":"pl-smi"},{"start":76,"end":100,"cssClass":"pl-s"},{"start":76,"end":77,"cssClass":"pl-pds"},{"start":77,"end":99,"cssClass":"pl-smi"},{"start":99,"end":100,"cssClass":"pl-pds"},{"start":101,"end":113,"cssClass":"pl-s"},{"start":101,"end":102,"cssClass":"pl-pds"},{"start":102,"end":112,"cssClass":"pl-smi"},{"start":112,"end":113,"cssClass":"pl-pds"},{"start":113,"end":114,"cssClass":"pl-k"},{"start":115,"end":117,"cssClass":"pl-k"}],[{"start":4,"end":6,"cssClass":"pl-k"},{"start":10,"end":36,"cssClass":"pl-s"},{"start":10,"end":12,"cssClass":"pl-pds"},{"start":16,"end":35,"cssClass":"pl-s"},{"start":16,"end":17,"cssClass":"pl-pds"},{"start":17,"end":34,"cssClass":"pl-smi"},{"start":34,"end":35,"cssClass":"pl-pds"},{"start":35,"end":36,"cssClass":"pl-pds"},{"start":37,"end":40,"cssClass":"pl-k"},{"start":41,"end":60,"cssClass":"pl-s"},{"start":41,"end":43,"cssClass":"pl-pds"},{"start":47,"end":59,"cssClass":"pl-s"},{"start":47,"end":48,"cssClass":"pl-pds"},{"start":58,"end":59,"cssClass":"pl-pds"},{"start":59,"end":60,"cssClass":"pl-pds"},{"start":61,"end":63,"cssClass":"pl-k"},{"start":64,"end":90,"cssClass":"pl-s"},{"start":64,"end":66,"cssClass":"pl-pds"},{"start":70,"end":89,"cssClass":"pl-s"},{"start":70,"end":71,"cssClass":"pl-pds"},{"start":71,"end":88,"cssClass":"pl-smi"},{"start":88,"end":89,"cssClass":"pl-pds"},{"start":89,"end":90,"cssClass":"pl-pds"},{"start":91,"end":94,"cssClass":"pl-k"},{"start":95,"end":114,"cssClass":"pl-s"},{"start":95,"end":97,"cssClass":"pl-pds"},{"start":101,"end":113,"cssClass":"pl-s"},{"start":101,"end":102,"cssClass":"pl-pds"},{"start":112,"end":113,"cssClass":"pl-pds"},{"start":113,"end":114,"cssClass":"pl-pds"},{"start":117,"end":118,"cssClass":"pl-k"},{"start":119,"end":123,"cssClass":"pl-k"},{"start":124,"end":129,"cssClass":"pl-smi"},{"start":130,"end":154,"cssClass":"pl-s"},{"start":130,"end":131,"cssClass":"pl-pds"},{"start":131,"end":153,"cssClass":"pl-smi"},{"start":153,"end":154,"cssClass":"pl-pds"},{"start":155,"end":167,"cssClass":"pl-s"},{"start":155,"end":156,"cssClass":"pl-pds"},{"start":156,"end":166,"cssClass":"pl-smi"},{"start":166,"end":167,"cssClass":"pl-pds"},{"start":167,"end":168,"cssClass":"pl-k"},{"start":169,"end":171,"cssClass":"pl-k"}],[{"start":4,"end":6,"cssClass":"pl-k"},{"start":10,"end":36,"cssClass":"pl-s"},{"start":10,"end":12,"cssClass":"pl-pds"},{"start":16,"end":35,"cssClass":"pl-s"},{"start":16,"end":17,"cssClass":"pl-pds"},{"start":17,"end":34,"cssClass":"pl-smi"},{"start":34,"end":35,"cssClass":"pl-pds"},{"start":35,"end":36,"cssClass":"pl-pds"},{"start":37,"end":40,"cssClass":"pl-k"},{"start":41,"end":60,"cssClass":"pl-s"},{"start":41,"end":43,"cssClass":"pl-pds"},{"start":47,"end":59,"cssClass":"pl-s"},{"start":47,"end":48,"cssClass":"pl-pds"},{"start":58,"end":59,"cssClass":"pl-pds"},{"start":59,"end":60,"cssClass":"pl-pds"},{"start":63,"end":64,"cssClass":"pl-k"},{"start":65,"end":69,"cssClass":"pl-k"},{"start":70,"end":75,"cssClass":"pl-smi"},{"start":76,"end":103,"cssClass":"pl-s"},{"start":76,"end":77,"cssClass":"pl-pds"},{"start":77,"end":102,"cssClass":"pl-smi"},{"start":102,"end":103,"cssClass":"pl-pds"},{"start":104,"end":116,"cssClass":"pl-s"},{"start":104,"end":105,"cssClass":"pl-pds"},{"start":105,"end":115,"cssClass":"pl-smi"},{"start":115,"end":116,"cssClass":"pl-pds"},{"start":116,"end":117,"cssClass":"pl-k"},{"start":118,"end":120,"cssClass":"pl-k"}],[{"start":4,"end":6,"cssClass":"pl-k"},{"start":10,"end":36,"cssClass":"pl-s"},{"start":10,"end":12,"cssClass":"pl-pds"},{"start":16,"end":35,"cssClass":"pl-s"},{"start":16,"end":17,"cssClass":"pl-pds"},{"start":17,"end":34,"cssClass":"pl-smi"},{"start":34,"end":35,"cssClass":"pl-pds"},{"start":35,"end":36,"cssClass":"pl-pds"},{"start":37,"end":40,"cssClass":"pl-k"},{"start":41,"end":60,"cssClass":"pl-s"},{"start":41,"end":43,"cssClass":"pl-pds"},{"start":47,"end":59,"cssClass":"pl-s"},{"start":47,"end":48,"cssClass":"pl-pds"},{"start":58,"end":59,"cssClass":"pl-pds"},{"start":59,"end":60,"cssClass":"pl-pds"},{"start":61,"end":63,"cssClass":"pl-k"},{"start":64,"end":90,"cssClass":"pl-s"},{"start":64,"end":66,"cssClass":"pl-pds"},{"start":70,"end":89,"cssClass":"pl-s"},{"start":70,"end":71,"cssClass":"pl-pds"},{"start":71,"end":88,"cssClass":"pl-smi"},{"start":88,"end":89,"cssClass":"pl-pds"},{"start":89,"end":90,"cssClass":"pl-pds"},{"start":91,"end":94,"cssClass":"pl-k"},{"start":95,"end":114,"cssClass":"pl-s"},{"start":95,"end":97,"cssClass":"pl-pds"},{"start":101,"end":113,"cssClass":"pl-s"},{"start":101,"end":102,"cssClass":"pl-pds"},{"start":112,"end":113,"cssClass":"pl-pds"},{"start":113,"end":114,"cssClass":"pl-pds"},{"start":117,"end":118,"cssClass":"pl-k"},{"start":119,"end":123,"cssClass":"pl-k"},{"start":124,"end":129,"cssClass":"pl-smi"},{"start":130,"end":164,"cssClass":"pl-s"},{"start":130,"end":131,"cssClass":"pl-pds"},{"start":131,"end":163,"cssClass":"pl-smi"},{"start":163,"end":164,"cssClass":"pl-pds"},{"start":165,"end":177,"cssClass":"pl-s"},{"start":165,"end":166,"cssClass":"pl-pds"},{"start":166,"end":176,"cssClass":"pl-smi"},{"start":176,"end":177,"cssClass":"pl-pds"},{"start":177,"end":178,"cssClass":"pl-k"},{"start":179,"end":181,"cssClass":"pl-k"}],[{"start":4,"end":6,"cssClass":"pl-k"},{"start":10,"end":36,"cssClass":"pl-s"},{"start":10,"end":12,"cssClass":"pl-pds"},{"start":16,"end":35,"cssClass":"pl-s"},{"start":16,"end":17,"cssClass":"pl-pds"},{"start":17,"end":34,"cssClass":"pl-smi"},{"start":34,"end":35,"cssClass":"pl-pds"},{"start":35,"end":36,"cssClass":"pl-pds"},{"start":37,"end":40,"cssClass":"pl-k"},{"start":41,"end":60,"cssClass":"pl-s"},{"start":41,"end":43,"cssClass":"pl-pds"},{"start":47,"end":59,"cssClass":"pl-s"},{"start":47,"end":48,"cssClass":"pl-pds"},{"start":58,"end":59,"cssClass":"pl-pds"},{"start":59,"end":60,"cssClass":"pl-pds"},{"start":63,"end":64,"cssClass":"pl-k"},{"start":65,"end":69,"cssClass":"pl-k"},{"start":70,"end":75,"cssClass":"pl-smi"},{"start":76,"end":114,"cssClass":"pl-s"},{"start":76,"end":77,"cssClass":"pl-pds"},{"start":77,"end":113,"cssClass":"pl-smi"},{"start":113,"end":114,"cssClass":"pl-pds"},{"start":115,"end":127,"cssClass":"pl-s"},{"start":115,"end":116,"cssClass":"pl-pds"},{"start":116,"end":126,"cssClass":"pl-smi"},{"start":126,"end":127,"cssClass":"pl-pds"},{"start":127,"end":128,"cssClass":"pl-k"},{"start":129,"end":131,"cssClass":"pl-k"}],[{"start":4,"end":6,"cssClass":"pl-k"},{"start":10,"end":36,"cssClass":"pl-s"},{"start":10,"end":12,"cssClass":"pl-pds"},{"start":16,"end":35,"cssClass":"pl-s"},{"start":16,"end":17,"cssClass":"pl-pds"},{"start":17,"end":34,"cssClass":"pl-smi"},{"start":34,"end":35,"cssClass":"pl-pds"},{"start":35,"end":36,"cssClass":"pl-pds"},{"start":37,"end":40,"cssClass":"pl-k"},{"start":41,"end":60,"cssClass":"pl-s"},{"start":41,"end":43,"cssClass":"pl-pds"},{"start":47,"end":59,"cssClass":"pl-s"},{"start":47,"end":48,"cssClass":"pl-pds"},{"start":58,"end":59,"cssClass":"pl-pds"},{"start":59,"end":60,"cssClass":"pl-pds"},{"start":63,"end":64,"cssClass":"pl-k"},{"start":65,"end":69,"cssClass":"pl-k"},{"start":70,"end":75,"cssClass":"pl-smi"},{"start":76,"end":110,"cssClass":"pl-s"},{"start":76,"end":77,"cssClass":"pl-pds"},{"start":77,"end":109,"cssClass":"pl-smi"},{"start":109,"end":110,"cssClass":"pl-pds"},{"start":111,"end":123,"cssClass":"pl-s"},{"start":111,"end":112,"cssClass":"pl-pds"},{"start":112,"end":122,"cssClass":"pl-smi"},{"start":122,"end":123,"cssClass":"pl-pds"},{"start":123,"end":124,"cssClass":"pl-k"},{"start":125,"end":127,"cssClass":"pl-k"}],[{"start":4,"end":6,"cssClass":"pl-k"},{"start":10,"end":36,"cssClass":"pl-s"},{"start":10,"end":12,"cssClass":"pl-pds"},{"start":16,"end":35,"cssClass":"pl-s"},{"start":16,"end":17,"cssClass":"pl-pds"},{"start":17,"end":34,"cssClass":"pl-smi"},{"start":34,"end":35,"cssClass":"pl-pds"},{"start":35,"end":36,"cssClass":"pl-pds"},{"start":37,"end":40,"cssClass":"pl-k"},{"start":41,"end":60,"cssClass":"pl-s"},{"start":41,"end":43,"cssClass":"pl-pds"},{"start":47,"end":59,"cssClass":"pl-s"},{"start":47,"end":48,"cssClass":"pl-pds"},{"start":58,"end":59,"cssClass":"pl-pds"},{"start":59,"end":60,"cssClass":"pl-pds"},{"start":63,"end":64,"cssClass":"pl-k"},{"start":65,"end":69,"cssClass":"pl-k"},{"start":70,"end":75,"cssClass":"pl-smi"},{"start":76,"end":104,"cssClass":"pl-s"},{"start":76,"end":77,"cssClass":"pl-pds"},{"start":77,"end":103,"cssClass":"pl-smi"},{"start":103,"end":104,"cssClass":"pl-pds"},{"start":105,"end":117,"cssClass":"pl-s"},{"start":105,"end":106,"cssClass":"pl-pds"},{"start":106,"end":116,"cssClass":"pl-smi"},{"start":116,"end":117,"cssClass":"pl-pds"},{"start":117,"end":118,"cssClass":"pl-k"},{"start":119,"end":121,"cssClass":"pl-k"}],[{"start":4,"end":6,"cssClass":"pl-k"},{"start":10,"end":36,"cssClass":"pl-s"},{"start":10,"end":12,"cssClass":"pl-pds"},{"start":16,"end":35,"cssClass":"pl-s"},{"start":16,"end":17,"cssClass":"pl-pds"},{"start":17,"end":34,"cssClass":"pl-smi"},{"start":34,"end":35,"cssClass":"pl-pds"},{"start":35,"end":36,"cssClass":"pl-pds"},{"start":37,"end":40,"cssClass":"pl-k"},{"start":41,"end":60,"cssClass":"pl-s"},{"start":41,"end":43,"cssClass":"pl-pds"},{"start":47,"end":59,"cssClass":"pl-s"},{"start":47,"end":48,"cssClass":"pl-pds"},{"start":58,"end":59,"cssClass":"pl-pds"},{"start":59,"end":60,"cssClass":"pl-pds"},{"start":61,"end":63,"cssClass":"pl-k"},{"start":64,"end":90,"cssClass":"pl-s"},{"start":64,"end":66,"cssClass":"pl-pds"},{"start":70,"end":89,"cssClass":"pl-s"},{"start":70,"end":71,"cssClass":"pl-pds"},{"start":71,"end":88,"cssClass":"pl-smi"},{"start":88,"end":89,"cssClass":"pl-pds"},{"start":89,"end":90,"cssClass":"pl-pds"},{"start":91,"end":94,"cssClass":"pl-k"},{"start":95,"end":114,"cssClass":"pl-s"},{"start":95,"end":97,"cssClass":"pl-pds"},{"start":101,"end":113,"cssClass":"pl-s"},{"start":101,"end":102,"cssClass":"pl-pds"},{"start":112,"end":113,"cssClass":"pl-pds"},{"start":113,"end":114,"cssClass":"pl-pds"},{"start":117,"end":118,"cssClass":"pl-k"},{"start":119,"end":123,"cssClass":"pl-k"},{"start":124,"end":129,"cssClass":"pl-smi"},{"start":130,"end":152,"cssClass":"pl-s"},{"start":130,"end":131,"cssClass":"pl-pds"},{"start":131,"end":151,"cssClass":"pl-smi"},{"start":151,"end":152,"cssClass":"pl-pds"},{"start":153,"end":165,"cssClass":"pl-s"},{"start":153,"end":154,"cssClass":"pl-pds"},{"start":154,"end":164,"cssClass":"pl-smi"},{"start":164,"end":165,"cssClass":"pl-pds"},{"start":165,"end":166,"cssClass":"pl-k"},{"start":167,"end":169,"cssClass":"pl-k"}],[{"start":4,"end":6,"cssClass":"pl-k"},{"start":10,"end":36,"cssClass":"pl-s"},{"start":10,"end":12,"cssClass":"pl-pds"},{"start":16,"end":35,"cssClass":"pl-s"},{"start":16,"end":17,"cssClass":"pl-pds"},{"start":17,"end":34,"cssClass":"pl-smi"},{"start":34,"end":35,"cssClass":"pl-pds"},{"start":35,"end":36,"cssClass":"pl-pds"},{"start":37,"end":40,"cssClass":"pl-k"},{"start":41,"end":60,"cssClass":"pl-s"},{"start":41,"end":43,"cssClass":"pl-pds"},{"start":47,"end":59,"cssClass":"pl-s"},{"start":47,"end":48,"cssClass":"pl-pds"},{"start":58,"end":59,"cssClass":"pl-pds"},{"start":59,"end":60,"cssClass":"pl-pds"},{"start":63,"end":64,"cssClass":"pl-k"},{"start":65,"end":69,"cssClass":"pl-k"},{"start":70,"end":75,"cssClass":"pl-smi"},{"start":76,"end":104,"cssClass":"pl-s"},{"start":76,"end":77,"cssClass":"pl-pds"},{"start":77,"end":103,"cssClass":"pl-smi"},{"start":103,"end":104,"cssClass":"pl-pds"},{"start":105,"end":117,"cssClass":"pl-s"},{"start":105,"end":106,"cssClass":"pl-pds"},{"start":106,"end":116,"cssClass":"pl-smi"},{"start":116,"end":117,"cssClass":"pl-pds"},{"start":117,"end":118,"cssClass":"pl-k"},{"start":119,"end":121,"cssClass":"pl-k"},{"start":121,"end":122,"cssClass":"pl-k"},{"start":123,"end":125,"cssClass":"pl-k"},{"start":125,"end":126,"cssClass":"pl-k"},{"start":127,"end":129,"cssClass":"pl-k"}],[],[{"start":0,"end":16,"cssClass":"pl-c"},{"start":0,"end":1,"cssClass":"pl-c"}],[{"start":0,"end":2,"cssClass":"pl-k"},{"start":6,"end":20,"cssClass":"pl-s"},{"start":6,"end":7,"cssClass":"pl-pds"},{"start":7,"end":19,"cssClass":"pl-smi"},{"start":19,"end":20,"cssClass":"pl-pds"},{"start":21,"end":23,"cssClass":"pl-k"},{"start":24,"end":31,"cssClass":"pl-s"},{"start":24,"end":25,"cssClass":"pl-pds"},{"start":30,"end":31,"cssClass":"pl-pds"},{"start":34,"end":35,"cssClass":"pl-k"},{"start":36,"end":40,"cssClass":"pl-k"}],[{"start":2,"end":6,"cssClass":"pl-c1"},{"start":7,"end":28,"cssClass":"pl-s"},{"start":7,"end":8,"cssClass":"pl-pds"},{"start":27,"end":28,"cssClass":"pl-pds"}],[{"start":2,"end":7,"cssClass":"pl-smi"},{"start":8,"end":18,"cssClass":"pl-s"},{"start":8,"end":9,"cssClass":"pl-pds"},{"start":9,"end":17,"cssClass":"pl-smi"},{"start":17,"end":18,"cssClass":"pl-pds"},{"start":19,"end":31,"cssClass":"pl-s"},{"start":19,"end":20,"cssClass":"pl-pds"},{"start":20,"end":30,"cssClass":"pl-smi"},{"start":30,"end":31,"cssClass":"pl-pds"}],[{"start":2,"end":7,"cssClass":"pl-smi"},{"start":8,"end":23,"cssClass":"pl-s"},{"start":8,"end":9,"cssClass":"pl-pds"},{"start":9,"end":22,"cssClass":"pl-smi"},{"start":22,"end":23,"cssClass":"pl-pds"},{"start":24,"end":43,"cssClass":"pl-s"},{"start":24,"end":25,"cssClass":"pl-pds"},{"start":25,"end":42,"cssClass":"pl-smi"},{"start":42,"end":43,"cssClass":"pl-pds"},{"start":43,"end":44,"cssClass":"pl-k"},{"start":45,"end":47,"cssClass":"pl-k"}],[],[{"start":0,"end":27,"cssClass":"pl-c"},{"start":0,"end":1,"cssClass":"pl-c"}],[{"start":0,"end":2,"cssClass":"pl-k"},{"start":6,"end":20,"cssClass":"pl-s"},{"start":6,"end":7,"cssClass":"pl-pds"},{"start":7,"end":19,"cssClass":"pl-smi"},{"start":19,"end":20,"cssClass":"pl-pds"},{"start":21,"end":23,"cssClass":"pl-k"},{"start":24,"end":31,"cssClass":"pl-s"},{"start":24,"end":25,"cssClass":"pl-pds"},{"start":30,"end":31,"cssClass":"pl-pds"},{"start":34,"end":35,"cssClass":"pl-k"},{"start":36,"end":40,"cssClass":"pl-k"}],[{"start":2,"end":4,"cssClass":"pl-k"},{"start":8,"end":24,"cssClass":"pl-s"},{"start":8,"end":9,"cssClass":"pl-pds"},{"start":9,"end":23,"cssClass":"pl-smi"},{"start":23,"end":24,"cssClass":"pl-pds"},{"start":25,"end":27,"cssClass":"pl-k"},{"start":28,"end":34,"cssClass":"pl-s"},{"start":28,"end":29,"cssClass":"pl-pds"},{"start":33,"end":34,"cssClass":"pl-pds"},{"start":37,"end":38,"cssClass":"pl-k"},{"start":39,"end":43,"cssClass":"pl-k"}],[{"start":4,"end":8,"cssClass":"pl-c1"},{"start":9,"end":40,"cssClass":"pl-s"},{"start":9,"end":10,"cssClass":"pl-pds"},{"start":39,"end":40,"cssClass":"pl-pds"}],[{"start":2,"end":6,"cssClass":"pl-k"},{"start":10,"end":36,"cssClass":"pl-s"},{"start":10,"end":12,"cssClass":"pl-pds"},{"start":16,"end":35,"cssClass":"pl-s"},{"start":16,"end":17,"cssClass":"pl-pds"},{"start":17,"end":34,"cssClass":"pl-smi"},{"start":34,"end":35,"cssClass":"pl-pds"},{"start":35,"end":36,"cssClass":"pl-pds"},{"start":37,"end":40,"cssClass":"pl-k"},{"start":41,"end":60,"cssClass":"pl-s"},{"start":41,"end":43,"cssClass":"pl-pds"},{"start":47,"end":59,"cssClass":"pl-s"},{"start":47,"end":48,"cssClass":"pl-pds"},{"start":58,"end":59,"cssClass":"pl-pds"},{"start":59,"end":60,"cssClass":"pl-pds"},{"start":61,"end":63,"cssClass":"pl-k"},{"start":64,"end":90,"cssClass":"pl-s"},{"start":64,"end":66,"cssClass":"pl-pds"},{"start":70,"end":89,"cssClass":"pl-s"},{"start":70,"end":71,"cssClass":"pl-pds"},{"start":71,"end":88,"cssClass":"pl-smi"},{"start":88,"end":89,"cssClass":"pl-pds"},{"start":89,"end":90,"cssClass":"pl-pds"},{"start":91,"end":94,"cssClass":"pl-k"},{"start":95,"end":114,"cssClass":"pl-s"},{"start":95,"end":97,"cssClass":"pl-pds"},{"start":101,"end":113,"cssClass":"pl-s"},{"start":101,"end":102,"cssClass":"pl-pds"},{"start":112,"end":113,"cssClass":"pl-pds"},{"start":113,"end":114,"cssClass":"pl-pds"},{"start":117,"end":118,"cssClass":"pl-k"},{"start":119,"end":123,"cssClass":"pl-k"}],[{"start":4,"end":8,"cssClass":"pl-c1"},{"start":9,"end":41,"cssClass":"pl-s"},{"start":9,"end":10,"cssClass":"pl-pds"},{"start":40,"end":41,"cssClass":"pl-pds"}],[{"start":4,"end":9,"cssClass":"pl-smi"},{"start":10,"end":21,"cssClass":"pl-s"},{"start":10,"end":11,"cssClass":"pl-pds"},{"start":11,"end":20,"cssClass":"pl-smi"},{"start":20,"end":21,"cssClass":"pl-pds"},{"start":22,"end":34,"cssClass":"pl-s"},{"start":22,"end":23,"cssClass":"pl-pds"},{"start":23,"end":33,"cssClass":"pl-smi"},{"start":33,"end":34,"cssClass":"pl-pds"}],[{"start":4,"end":9,"cssClass":"pl-smi"},{"start":10,"end":33,"cssClass":"pl-s"},{"start":10,"end":11,"cssClass":"pl-pds"},{"start":11,"end":32,"cssClass":"pl-smi"},{"start":32,"end":33,"cssClass":"pl-pds"},{"start":34,"end":46,"cssClass":"pl-s"},{"start":34,"end":35,"cssClass":"pl-pds"},{"start":35,"end":45,"cssClass":"pl-smi"},{"start":45,"end":46,"cssClass":"pl-pds"}],[{"start":2,"end":6,"cssClass":"pl-k"},{"start":10,"end":36,"cssClass":"pl-s"},{"start":10,"end":12,"cssClass":"pl-pds"},{"start":16,"end":35,"cssClass":"pl-s"},{"start":16,"end":17,"cssClass":"pl-pds"},{"start":17,"end":34,"cssClass":"pl-smi"},{"start":34,"end":35,"cssClass":"pl-pds"},{"start":35,"end":36,"cssClass":"pl-pds"},{"start":37,"end":40,"cssClass":"pl-k"},{"start":41,"end":60,"cssClass":"pl-s"},{"start":41,"end":43,"cssClass":"pl-pds"},{"start":47,"end":59,"cssClass":"pl-s"},{"start":47,"end":48,"cssClass":"pl-pds"},{"start":58,"end":59,"cssClass":"pl-pds"},{"start":59,"end":60,"cssClass":"pl-pds"},{"start":61,"end":63,"cssClass":"pl-k"},{"start":64,"end":90,"cssClass":"pl-s"},{"start":64,"end":66,"cssClass":"pl-pds"},{"start":70,"end":89,"cssClass":"pl-s"},{"start":70,"end":71,"cssClass":"pl-pds"},{"start":71,"end":88,"cssClass":"pl-smi"},{"start":88,"end":89,"cssClass":"pl-pds"},{"start":89,"end":90,"cssClass":"pl-pds"},{"start":91,"end":94,"cssClass":"pl-k"},{"start":95,"end":114,"cssClass":"pl-s"},{"start":95,"end":97,"cssClass":"pl-pds"},{"start":101,"end":113,"cssClass":"pl-s"},{"start":101,"end":102,"cssClass":"pl-pds"},{"start":112,"end":113,"cssClass":"pl-pds"},{"start":113,"end":114,"cssClass":"pl-pds"},{"start":117,"end":118,"cssClass":"pl-k"},{"start":119,"end":123,"cssClass":"pl-k"}],[{"start":4,"end":8,"cssClass":"pl-c1"},{"start":9,"end":41,"cssClass":"pl-s"},{"start":9,"end":10,"cssClass":"pl-pds"},{"start":40,"end":41,"cssClass":"pl-pds"}],[{"start":4,"end":9,"cssClass":"pl-smi"},{"start":10,"end":23,"cssClass":"pl-s"},{"start":10,"end":11,"cssClass":"pl-pds"},{"start":11,"end":22,"cssClass":"pl-smi"},{"start":22,"end":23,"cssClass":"pl-pds"},{"start":24,"end":36,"cssClass":"pl-s"},{"start":24,"end":25,"cssClass":"pl-pds"},{"start":25,"end":35,"cssClass":"pl-smi"},{"start":35,"end":36,"cssClass":"pl-pds"}],[{"start":4,"end":9,"cssClass":"pl-smi"},{"start":10,"end":33,"cssClass":"pl-s"},{"start":10,"end":11,"cssClass":"pl-pds"},{"start":11,"end":32,"cssClass":"pl-smi"},{"start":32,"end":33,"cssClass":"pl-pds"},{"start":34,"end":46,"cssClass":"pl-s"},{"start":34,"end":35,"cssClass":"pl-pds"},{"start":35,"end":45,"cssClass":"pl-smi"},{"start":45,"end":46,"cssClass":"pl-pds"}],[{"start":4,"end":6,"cssClass":"pl-k"},{"start":10,"end":36,"cssClass":"pl-s"},{"start":10,"end":12,"cssClass":"pl-pds"},{"start":16,"end":35,"cssClass":"pl-s"},{"start":16,"end":17,"cssClass":"pl-pds"},{"start":17,"end":34,"cssClass":"pl-smi"},{"start":34,"end":35,"cssClass":"pl-pds"},{"start":35,"end":36,"cssClass":"pl-pds"},{"start":37,"end":40,"cssClass":"pl-k"},{"start":41,"end":60,"cssClass":"pl-s"},{"start":41,"end":43,"cssClass":"pl-pds"},{"start":47,"end":59,"cssClass":"pl-s"},{"start":47,"end":48,"cssClass":"pl-pds"},{"start":58,"end":59,"cssClass":"pl-pds"},{"start":59,"end":60,"cssClass":"pl-pds"},{"start":63,"end":64,"cssClass":"pl-k"},{"start":65,"end":69,"cssClass":"pl-k"},{"start":70,"end":75,"cssClass":"pl-smi"},{"start":76,"end":101,"cssClass":"pl-s"},{"start":76,"end":77,"cssClass":"pl-pds"},{"start":77,"end":100,"cssClass":"pl-smi"},{"start":100,"end":101,"cssClass":"pl-pds"},{"start":102,"end":114,"cssClass":"pl-s"},{"start":102,"end":103,"cssClass":"pl-pds"},{"start":103,"end":113,"cssClass":"pl-smi"},{"start":113,"end":114,"cssClass":"pl-pds"},{"start":114,"end":115,"cssClass":"pl-k"},{"start":116,"end":118,"cssClass":"pl-k"}],[{"start":4,"end":6,"cssClass":"pl-k"},{"start":10,"end":36,"cssClass":"pl-s"},{"start":10,"end":12,"cssClass":"pl-pds"},{"start":16,"end":35,"cssClass":"pl-s"},{"start":16,"end":17,"cssClass":"pl-pds"},{"start":17,"end":34,"cssClass":"pl-smi"},{"start":34,"end":35,"cssClass":"pl-pds"},{"start":35,"end":36,"cssClass":"pl-pds"},{"start":37,"end":40,"cssClass":"pl-k"},{"start":41,"end":60,"cssClass":"pl-s"},{"start":41,"end":43,"cssClass":"pl-pds"},{"start":47,"end":59,"cssClass":"pl-s"},{"start":47,"end":48,"cssClass":"pl-pds"},{"start":58,"end":59,"cssClass":"pl-pds"},{"start":59,"end":60,"cssClass":"pl-pds"},{"start":63,"end":64,"cssClass":"pl-k"},{"start":65,"end":69,"cssClass":"pl-k"},{"start":70,"end":75,"cssClass":"pl-smi"},{"start":76,"end":108,"cssClass":"pl-s"},{"start":76,"end":77,"cssClass":"pl-pds"},{"start":77,"end":107,"cssClass":"pl-smi"},{"start":107,"end":108,"cssClass":"pl-pds"},{"start":109,"end":121,"cssClass":"pl-s"},{"start":109,"end":110,"cssClass":"pl-pds"},{"start":110,"end":120,"cssClass":"pl-smi"},{"start":120,"end":121,"cssClass":"pl-pds"},{"start":121,"end":122,"cssClass":"pl-k"},{"start":123,"end":125,"cssClass":"pl-k"}],[{"start":2,"end":6,"cssClass":"pl-k"},{"start":10,"end":36,"cssClass":"pl-s"},{"start":10,"end":12,"cssClass":"pl-pds"},{"start":16,"end":35,"cssClass":"pl-s"},{"start":16,"end":17,"cssClass":"pl-pds"},{"start":17,"end":34,"cssClass":"pl-smi"},{"start":34,"end":35,"cssClass":"pl-pds"},{"start":35,"end":36,"cssClass":"pl-pds"},{"start":37,"end":40,"cssClass":"pl-k"},{"start":41,"end":60,"cssClass":"pl-s"},{"start":41,"end":43,"cssClass":"pl-pds"},{"start":47,"end":59,"cssClass":"pl-s"},{"start":47,"end":48,"cssClass":"pl-pds"},{"start":58,"end":59,"cssClass":"pl-pds"},{"start":59,"end":60,"cssClass":"pl-pds"},{"start":63,"end":64,"cssClass":"pl-k"},{"start":65,"end":69,"cssClass":"pl-k"}],[{"start":4,"end":8,"cssClass":"pl-c1"},{"start":9,"end":41,"cssClass":"pl-s"},{"start":9,"end":10,"cssClass":"pl-pds"},{"start":40,"end":41,"cssClass":"pl-pds"}],[{"start":4,"end":9,"cssClass":"pl-smi"},{"start":10,"end":33,"cssClass":"pl-s"},{"start":10,"end":11,"cssClass":"pl-pds"},{"start":11,"end":32,"cssClass":"pl-smi"},{"start":32,"end":33,"cssClass":"pl-pds"},{"start":34,"end":46,"cssClass":"pl-s"},{"start":34,"end":35,"cssClass":"pl-pds"},{"start":35,"end":45,"cssClass":"pl-smi"},{"start":45,"end":46,"cssClass":"pl-pds"}],[{"start":4,"end":6,"cssClass":"pl-k"},{"start":10,"end":36,"cssClass":"pl-s"},{"start":10,"end":12,"cssClass":"pl-pds"},{"start":16,"end":35,"cssClass":"pl-s"},{"start":16,"end":17,"cssClass":"pl-pds"},{"start":17,"end":34,"cssClass":"pl-smi"},{"start":34,"end":35,"cssClass":"pl-pds"},{"start":35,"end":36,"cssClass":"pl-pds"},{"start":37,"end":40,"cssClass":"pl-k"},{"start":41,"end":60,"cssClass":"pl-s"},{"start":41,"end":43,"cssClass":"pl-pds"},{"start":47,"end":59,"cssClass":"pl-s"},{"start":47,"end":48,"cssClass":"pl-pds"},{"start":58,"end":59,"cssClass":"pl-pds"},{"start":59,"end":60,"cssClass":"pl-pds"},{"start":63,"end":64,"cssClass":"pl-k"},{"start":65,"end":69,"cssClass":"pl-k"},{"start":70,"end":75,"cssClass":"pl-smi"},{"start":76,"end":100,"cssClass":"pl-s"},{"start":76,"end":77,"cssClass":"pl-pds"},{"start":77,"end":99,"cssClass":"pl-smi"},{"start":99,"end":100,"cssClass":"pl-pds"},{"start":101,"end":113,"cssClass":"pl-s"},{"start":101,"end":102,"cssClass":"pl-pds"},{"start":102,"end":112,"cssClass":"pl-smi"},{"start":112,"end":113,"cssClass":"pl-pds"},{"start":113,"end":114,"cssClass":"pl-k"},{"start":115,"end":117,"cssClass":"pl-k"}],[{"start":4,"end":6,"cssClass":"pl-k"},{"start":10,"end":36,"cssClass":"pl-s"},{"start":10,"end":12,"cssClass":"pl-pds"},{"start":16,"end":35,"cssClass":"pl-s"},{"start":16,"end":17,"cssClass":"pl-pds"},{"start":17,"end":34,"cssClass":"pl-smi"},{"start":34,"end":35,"cssClass":"pl-pds"},{"start":35,"end":36,"cssClass":"pl-pds"},{"start":37,"end":40,"cssClass":"pl-k"},{"start":41,"end":60,"cssClass":"pl-s"},{"start":41,"end":43,"cssClass":"pl-pds"},{"start":47,"end":59,"cssClass":"pl-s"},{"start":47,"end":48,"cssClass":"pl-pds"},{"start":58,"end":59,"cssClass":"pl-pds"},{"start":59,"end":60,"cssClass":"pl-pds"},{"start":63,"end":64,"cssClass":"pl-k"},{"start":65,"end":69,"cssClass":"pl-k"},{"start":70,"end":75,"cssClass":"pl-smi"},{"start":76,"end":101,"cssClass":"pl-s"},{"start":76,"end":77,"cssClass":"pl-pds"},{"start":77,"end":100,"cssClass":"pl-smi"},{"start":100,"end":101,"cssClass":"pl-pds"},{"start":102,"end":114,"cssClass":"pl-s"},{"start":102,"end":103,"cssClass":"pl-pds"},{"start":103,"end":113,"cssClass":"pl-smi"},{"start":113,"end":114,"cssClass":"pl-pds"},{"start":114,"end":115,"cssClass":"pl-k"},{"start":116,"end":118,"cssClass":"pl-k"}],[{"start":4,"end":6,"cssClass":"pl-k"},{"start":10,"end":36,"cssClass":"pl-s"},{"start":10,"end":12,"cssClass":"pl-pds"},{"start":16,"end":35,"cssClass":"pl-s"},{"start":16,"end":17,"cssClass":"pl-pds"},{"start":17,"end":34,"cssClass":"pl-smi"},{"start":34,"end":35,"cssClass":"pl-pds"},{"start":35,"end":36,"cssClass":"pl-pds"},{"start":37,"end":40,"cssClass":"pl-k"},{"start":41,"end":60,"cssClass":"pl-s"},{"start":41,"end":43,"cssClass":"pl-pds"},{"start":47,"end":59,"cssClass":"pl-s"},{"start":47,"end":48,"cssClass":"pl-pds"},{"start":58,"end":59,"cssClass":"pl-pds"},{"start":59,"end":60,"cssClass":"pl-pds"},{"start":63,"end":64,"cssClass":"pl-k"},{"start":65,"end":69,"cssClass":"pl-k"},{"start":70,"end":75,"cssClass":"pl-smi"},{"start":76,"end":108,"cssClass":"pl-s"},{"start":76,"end":77,"cssClass":"pl-pds"},{"start":77,"end":107,"cssClass":"pl-smi"},{"start":107,"end":108,"cssClass":"pl-pds"},{"start":109,"end":121,"cssClass":"pl-s"},{"start":109,"end":110,"cssClass":"pl-pds"},{"start":110,"end":120,"cssClass":"pl-smi"},{"start":120,"end":121,"cssClass":"pl-pds"},{"start":121,"end":122,"cssClass":"pl-k"},{"start":123,"end":125,"cssClass":"pl-k"}],[{"start":2,"end":6,"cssClass":"pl-k"}],[{"start":4,"end":5,"cssClass":"pl-c1"},{"start":5,"end":6,"cssClass":"pl-k"},{"start":7,"end":9,"cssClass":"pl-k"},{"start":9,"end":10,"cssClass":"pl-k"},{"start":11,"end":13,"cssClass":"pl-k"}],[],[{"start":0,"end":55,"cssClass":"pl-c"},{"start":0,"end":1,"cssClass":"pl-c"}],[{"start":0,"end":2,"cssClass":"pl-k"},{"start":6,"end":20,"cssClass":"pl-s"},{"start":6,"end":7,"cssClass":"pl-pds"},{"start":7,"end":19,"cssClass":"pl-smi"},{"start":19,"end":20,"cssClass":"pl-pds"},{"start":21,"end":23,"cssClass":"pl-k"},{"start":24,"end":31,"cssClass":"pl-s"},{"start":24,"end":25,"cssClass":"pl-pds"},{"start":30,"end":31,"cssClass":"pl-pds"},{"start":34,"end":35,"cssClass":"pl-k"},{"start":36,"end":40,"cssClass":"pl-k"}],[{"start":2,"end":4,"cssClass":"pl-k"},{"start":8,"end":31,"cssClass":"pl-s"},{"start":8,"end":9,"cssClass":"pl-pds"},{"start":9,"end":30,"cssClass":"pl-smi"},{"start":30,"end":31,"cssClass":"pl-pds"},{"start":32,"end":34,"cssClass":"pl-k"},{"start":35,"end":41,"cssClass":"pl-s"},{"start":35,"end":36,"cssClass":"pl-pds"},{"start":40,"end":41,"cssClass":"pl-pds"},{"start":44,"end":45,"cssClass":"pl-k"},{"start":46,"end":50,"cssClass":"pl-k"}],[{"start":4,"end":6,"cssClass":"pl-k"},{"start":10,"end":36,"cssClass":"pl-s"},{"start":10,"end":12,"cssClass":"pl-pds"},{"start":16,"end":35,"cssClass":"pl-s"},{"start":16,"end":17,"cssClass":"pl-pds"},{"start":17,"end":34,"cssClass":"pl-smi"},{"start":34,"end":35,"cssClass":"pl-pds"},{"start":35,"end":36,"cssClass":"pl-pds"},{"start":37,"end":40,"cssClass":"pl-k"},{"start":41,"end":60,"cssClass":"pl-s"},{"start":41,"end":43,"cssClass":"pl-pds"},{"start":47,"end":59,"cssClass":"pl-s"},{"start":47,"end":48,"cssClass":"pl-pds"},{"start":58,"end":59,"cssClass":"pl-pds"},{"start":59,"end":60,"cssClass":"pl-pds"},{"start":63,"end":64,"cssClass":"pl-k"},{"start":65,"end":69,"cssClass":"pl-k"}],[{"start":6,"end":10,"cssClass":"pl-c1"},{"start":11,"end":53,"cssClass":"pl-s"},{"start":11,"end":12,"cssClass":"pl-pds"},{"start":52,"end":53,"cssClass":"pl-pds"}],[{"start":6,"end":11,"cssClass":"pl-smi"},{"start":12,"end":30,"cssClass":"pl-s"},{"start":12,"end":13,"cssClass":"pl-pds"},{"start":13,"end":29,"cssClass":"pl-smi"},{"start":29,"end":30,"cssClass":"pl-pds"},{"start":31,"end":43,"cssClass":"pl-s"},{"start":31,"end":32,"cssClass":"pl-pds"},{"start":32,"end":42,"cssClass":"pl-smi"},{"start":42,"end":43,"cssClass":"pl-pds"}],[{"start":4,"end":8,"cssClass":"pl-k"},{"start":12,"end":38,"cssClass":"pl-s"},{"start":12,"end":14,"cssClass":"pl-pds"},{"start":18,"end":37,"cssClass":"pl-s"},{"start":18,"end":19,"cssClass":"pl-pds"},{"start":19,"end":36,"cssClass":"pl-smi"},{"start":36,"end":37,"cssClass":"pl-pds"},{"start":37,"end":38,"cssClass":"pl-pds"},{"start":39,"end":42,"cssClass":"pl-k"},{"start":43,"end":62,"cssClass":"pl-s"},{"start":43,"end":45,"cssClass":"pl-pds"},{"start":49,"end":61,"cssClass":"pl-s"},{"start":49,"end":50,"cssClass":"pl-pds"},{"start":60,"end":61,"cssClass":"pl-pds"},{"start":61,"end":62,"cssClass":"pl-pds"},{"start":63,"end":65,"cssClass":"pl-k"},{"start":66,"end":92,"cssClass":"pl-s"},{"start":66,"end":68,"cssClass":"pl-pds"},{"start":72,"end":91,"cssClass":"pl-s"},{"start":72,"end":73,"cssClass":"pl-pds"},{"start":73,"end":90,"cssClass":"pl-smi"},{"start":90,"end":91,"cssClass":"pl-pds"},{"start":91,"end":92,"cssClass":"pl-pds"},{"start":93,"end":96,"cssClass":"pl-k"},{"start":97,"end":116,"cssClass":"pl-s"},{"start":97,"end":99,"cssClass":"pl-pds"},{"start":103,"end":115,"cssClass":"pl-s"},{"start":103,"end":104,"cssClass":"pl-pds"},{"start":114,"end":115,"cssClass":"pl-pds"},{"start":115,"end":116,"cssClass":"pl-pds"},{"start":119,"end":120,"cssClass":"pl-k"},{"start":121,"end":125,"cssClass":"pl-k"}],[{"start":6,"end":10,"cssClass":"pl-c1"},{"start":11,"end":53,"cssClass":"pl-s"},{"start":11,"end":12,"cssClass":"pl-pds"},{"start":52,"end":53,"cssClass":"pl-pds"}],[{"start":6,"end":11,"cssClass":"pl-smi"},{"start":12,"end":31,"cssClass":"pl-s"},{"start":12,"end":13,"cssClass":"pl-pds"},{"start":13,"end":30,"cssClass":"pl-smi"},{"start":30,"end":31,"cssClass":"pl-pds"},{"start":32,"end":47,"cssClass":"pl-s"},{"start":32,"end":33,"cssClass":"pl-pds"},{"start":33,"end":46,"cssClass":"pl-smi"},{"start":46,"end":47,"cssClass":"pl-pds"}],[{"start":4,"end":8,"cssClass":"pl-k"},{"start":12,"end":38,"cssClass":"pl-s"},{"start":12,"end":14,"cssClass":"pl-pds"},{"start":18,"end":37,"cssClass":"pl-s"},{"start":18,"end":19,"cssClass":"pl-pds"},{"start":19,"end":36,"cssClass":"pl-smi"},{"start":36,"end":37,"cssClass":"pl-pds"},{"start":37,"end":38,"cssClass":"pl-pds"},{"start":39,"end":42,"cssClass":"pl-k"},{"start":43,"end":62,"cssClass":"pl-s"},{"start":43,"end":45,"cssClass":"pl-pds"},{"start":49,"end":61,"cssClass":"pl-s"},{"start":49,"end":50,"cssClass":"pl-pds"},{"start":60,"end":61,"cssClass":"pl-pds"},{"start":61,"end":62,"cssClass":"pl-pds"},{"start":63,"end":65,"cssClass":"pl-k"},{"start":66,"end":92,"cssClass":"pl-s"},{"start":66,"end":68,"cssClass":"pl-pds"},{"start":72,"end":91,"cssClass":"pl-s"},{"start":72,"end":73,"cssClass":"pl-pds"},{"start":73,"end":90,"cssClass":"pl-smi"},{"start":90,"end":91,"cssClass":"pl-pds"},{"start":91,"end":92,"cssClass":"pl-pds"},{"start":93,"end":96,"cssClass":"pl-k"},{"start":97,"end":116,"cssClass":"pl-s"},{"start":97,"end":99,"cssClass":"pl-pds"},{"start":103,"end":115,"cssClass":"pl-s"},{"start":103,"end":104,"cssClass":"pl-pds"},{"start":114,"end":115,"cssClass":"pl-pds"},{"start":115,"end":116,"cssClass":"pl-pds"},{"start":119,"end":120,"cssClass":"pl-k"},{"start":121,"end":125,"cssClass":"pl-k"}],[{"start":6,"end":10,"cssClass":"pl-c1"},{"start":11,"end":53,"cssClass":"pl-s"},{"start":11,"end":12,"cssClass":"pl-pds"},{"start":52,"end":53,"cssClass":"pl-pds"}],[{"start":6,"end":11,"cssClass":"pl-smi"},{"start":12,"end":31,"cssClass":"pl-s"},{"start":12,"end":13,"cssClass":"pl-pds"},{"start":13,"end":30,"cssClass":"pl-smi"},{"start":30,"end":31,"cssClass":"pl-pds"},{"start":32,"end":47,"cssClass":"pl-s"},{"start":32,"end":33,"cssClass":"pl-pds"},{"start":33,"end":46,"cssClass":"pl-smi"},{"start":46,"end":47,"cssClass":"pl-pds"}],[{"start":4,"end":8,"cssClass":"pl-k"},{"start":12,"end":38,"cssClass":"pl-s"},{"start":12,"end":14,"cssClass":"pl-pds"},{"start":18,"end":37,"cssClass":"pl-s"},{"start":18,"end":19,"cssClass":"pl-pds"},{"start":19,"end":36,"cssClass":"pl-smi"},{"start":36,"end":37,"cssClass":"pl-pds"},{"start":37,"end":38,"cssClass":"pl-pds"},{"start":39,"end":42,"cssClass":"pl-k"},{"start":43,"end":62,"cssClass":"pl-s"},{"start":43,"end":45,"cssClass":"pl-pds"},{"start":49,"end":61,"cssClass":"pl-s"},{"start":49,"end":50,"cssClass":"pl-pds"},{"start":60,"end":61,"cssClass":"pl-pds"},{"start":61,"end":62,"cssClass":"pl-pds"},{"start":65,"end":66,"cssClass":"pl-k"},{"start":67,"end":71,"cssClass":"pl-k"}],[{"start":6,"end":10,"cssClass":"pl-c1"},{"start":11,"end":53,"cssClass":"pl-s"},{"start":11,"end":12,"cssClass":"pl-pds"},{"start":52,"end":53,"cssClass":"pl-pds"}],[{"start":6,"end":11,"cssClass":"pl-smi"},{"start":12,"end":31,"cssClass":"pl-s"},{"start":12,"end":13,"cssClass":"pl-pds"},{"start":13,"end":30,"cssClass":"pl-smi"},{"start":30,"end":31,"cssClass":"pl-pds"},{"start":32,"end":44,"cssClass":"pl-s"},{"start":32,"end":33,"cssClass":"pl-pds"},{"start":33,"end":43,"cssClass":"pl-smi"},{"start":43,"end":44,"cssClass":"pl-pds"},{"start":44,"end":45,"cssClass":"pl-k"},{"start":46,"end":48,"cssClass":"pl-k"},{"start":48,"end":49,"cssClass":"pl-k"},{"start":50,"end":52,"cssClass":"pl-k"},{"start":52,"end":53,"cssClass":"pl-k"},{"start":54,"end":56,"cssClass":"pl-k"}],[],[{"start":0,"end":18,"cssClass":"pl-c"},{"start":0,"end":1,"cssClass":"pl-c"}],[{"start":0,"end":2,"cssClass":"pl-k"},{"start":6,"end":21,"cssClass":"pl-s"},{"start":6,"end":7,"cssClass":"pl-pds"},{"start":7,"end":20,"cssClass":"pl-smi"},{"start":20,"end":21,"cssClass":"pl-pds"},{"start":22,"end":24,"cssClass":"pl-k"},{"start":25,"end":31,"cssClass":"pl-s"},{"start":25,"end":26,"cssClass":"pl-pds"},{"start":30,"end":31,"cssClass":"pl-pds"},{"start":34,"end":35,"cssClass":"pl-k"},{"start":36,"end":40,"cssClass":"pl-k"}],[{"start":2,"end":6,"cssClass":"pl-c1"},{"start":7,"end":30,"cssClass":"pl-s"},{"start":7,"end":8,"cssClass":"pl-pds"},{"start":29,"end":30,"cssClass":"pl-pds"}],[{"start":9,"end":22,"cssClass":"pl-s"},{"start":9,"end":10,"cssClass":"pl-pds"},{"start":10,"end":21,"cssClass":"pl-smi"},{"start":21,"end":22,"cssClass":"pl-pds"},{"start":22,"end":23,"cssClass":"pl-k"},{"start":24,"end":26,"cssClass":"pl-k"}],[],[{"start":0,"end":18,"cssClass":"pl-c"},{"start":0,"end":1,"cssClass":"pl-c"}],[{"start":0,"end":2,"cssClass":"pl-k"},{"start":6,"end":20,"cssClass":"pl-s"},{"start":6,"end":7,"cssClass":"pl-pds"},{"start":7,"end":19,"cssClass":"pl-smi"},{"start":19,"end":20,"cssClass":"pl-pds"},{"start":21,"end":23,"cssClass":"pl-k"},{"start":24,"end":31,"cssClass":"pl-s"},{"start":24,"end":25,"cssClass":"pl-pds"},{"start":30,"end":31,"cssClass":"pl-pds"},{"start":34,"end":35,"cssClass":"pl-k"},{"start":36,"end":40,"cssClass":"pl-k"}],[{"start":2,"end":6,"cssClass":"pl-c1"},{"start":7,"end":27,"cssClass":"pl-s"},{"start":7,"end":8,"cssClass":"pl-pds"},{"start":26,"end":27,"cssClass":"pl-pds"}],[{"start":2,"end":6,"cssClass":"pl-c1"},{"start":10,"end":32,"cssClass":"pl-s"},{"start":10,"end":11,"cssClass":"pl-pds"},{"start":31,"end":32,"cssClass":"pl-pds"},{"start":33,"end":35,"cssClass":"pl-k"},{"start":36,"end":48,"cssClass":"pl-s"},{"start":36,"end":37,"cssClass":"pl-pds"},{"start":37,"end":47,"cssClass":"pl-smi"},{"start":47,"end":48,"cssClass":"pl-pds"},{"start":48,"end":49,"cssClass":"pl-k"},{"start":50,"end":52,"cssClass":"pl-k"}],[],[{"start":0,"end":30,"cssClass":"pl-c"},{"start":0,"end":1,"cssClass":"pl-c"}],[{"start":0,"end":2,"cssClass":"pl-k"},{"start":6,"end":20,"cssClass":"pl-s"},{"start":6,"end":7,"cssClass":"pl-pds"},{"start":7,"end":19,"cssClass":"pl-smi"},{"start":19,"end":20,"cssClass":"pl-pds"},{"start":21,"end":23,"cssClass":"pl-k"},{"start":24,"end":31,"cssClass":"pl-s"},{"start":24,"end":25,"cssClass":"pl-pds"},{"start":30,"end":31,"cssClass":"pl-pds"},{"start":34,"end":35,"cssClass":"pl-k"},{"start":36,"end":40,"cssClass":"pl-k"}],[{"start":6,"end":19,"cssClass":"pl-s"},{"start":6,"end":7,"cssClass":"pl-pds"},{"start":7,"end":18,"cssClass":"pl-smi"},{"start":18,"end":19,"cssClass":"pl-pds"},{"start":19,"end":20,"cssClass":"pl-k"}],[{"start":9,"end":22,"cssClass":"pl-s"},{"start":9,"end":10,"cssClass":"pl-pds"},{"start":10,"end":21,"cssClass":"pl-smi"},{"start":21,"end":22,"cssClass":"pl-pds"},{"start":22,"end":23,"cssClass":"pl-k"},{"start":24,"end":26,"cssClass":"pl-k"}],[],[{"start":0,"end":4,"cssClass":"pl-c1"},{"start":8,"end":36,"cssClass":"pl-s"},{"start":8,"end":9,"cssClass":"pl-pds"},{"start":35,"end":36,"cssClass":"pl-pds"}]],"csv":null,"csvError":null,"dependabotInfo":{"showConfigurationBanner":false,"configFilePath":null,"networkDependabotPath":"/SpotX-CLI/SpotX-Linux/network/updates","dismissConfigurationNoticePath":"/settings/dismiss-notice/dependabot_configuration_notice","configurationNoticeDismissed":false,"repoAlertsPath":"/SpotX-CLI/SpotX-Linux/security/dependabot","repoSecurityAndAnalysisPath":"/SpotX-CLI/SpotX-Linux/settings/security_analysis","repoOwnerIsOrg":true,"currentUserCanAdminRepo":false},"displayName":"install.sh","displayUrl":"https://github.com/SpotX-CLI/SpotX-Linux/blob/main/install.sh?raw=true","headerInfo":{"blobSize":"18.7 KB","deleteInfo":{"deletePath":"https://github.com/SpotX-CLI/SpotX-Linux/delete/main/install.sh","deleteTooltip":"Fork this repository and delete the file"},"editInfo":{"editTooltip":"Fork this repository and edit the file"},"ghDesktopPath":"x-github-client://openRepo/https://github.com/SpotX-CLI/SpotX-Linux?branch=main\u0026filepath=install.sh","gitLfsPath":null,"onBranch":true,"shortPath":"18b6962","siteNavLoginPath":"/login?return_to=https%3A%2F%2Fgithub.com%2FSpotX-CLI%2FSpotX-Linux%2Fblob%2Fmain%2Finstall.sh","isCSV":false,"isRichtext":false,"toc":null,"lineInfo":{"truncatedLoc":"339","truncatedSloc":"305"},"mode":"file"},"image":false,"isCodeownersFile":null,"isValidLegacyIssueTemplate":false,"issueTemplateHelpUrl":"https://docs.github.com/articles/about-issue-and-pull-request-templates","issueTemplate":null,"discussionTemplate":null,"language":"Shell","large":false,"loggedIn":true,"newDiscussionPath":"/SpotX-CLI/SpotX-Linux/discussions/new","newIssuePath":"/SpotX-CLI/SpotX-Linux/issues/new","planSupportInfo":{"repoIsFork":null,"repoOwnedByCurrentUser":null,"requestFullPath":"/SpotX-CLI/SpotX-Linux/blob/main/install.sh","showFreeOrgGatedFeatureMessage":null,"showPlanSupportBanner":null,"upgradeDataAttributes":null,"upgradePath":null},"publishBannersInfo":{"dismissActionNoticePath":"/settings/dismiss-notice/publish_action_from_dockerfile","dismissStackNoticePath":"/settings/dismiss-notice/publish_stack_from_file","releasePath":"/SpotX-CLI/SpotX-Linux/releases/new?marketplace=true","showPublishActionBanner":false,"showPublishStackBanner":false},"renderImageOrRaw":false,"richText":null,"renderedFileInfo":null,"tabSize":8,"topBannersInfo":{"overridingGlobalFundingFile":false,"globalPreferredFundingPath":null,"repoOwner":"SpotX-CLI","repoName":"SpotX-Linux","showInvalidCitationWarning":false,"citationHelpUrl":"https://docs.github.com/en/github/creating-cloning-and-archiving-repositories/creating-a-repository-on-github/about-citation-files","showDependabotConfigurationBanner":false,"actionsOnboardingTip":null},"truncated":false,"viewable":true,"workflowRedirectUrl":null,"symbols":{"timedOut":false,"notAnalyzed":false,"symbols":[{"name":"ver","kind":"function","identStart":8992,"identEnd":8995,"extentStart":8983,"extentEnd":9067,"fullyQualifiedName":"ver","identUtf16":{"start":{"lineNumber":150,"utf16Col":9},"end":{"lineNumber":150,"utf16Col":12}},"extentUtf16":{"start":{"lineNumber":150,"utf16Col":0},"end":{"lineNumber":150,"utf16Col":84}}}]}},"csrf_tokens":{"/SpotX-CLI/SpotX-Linux/branches":{"post":"4FVWnihv25ztUuHDRk6xqocoKiYR6P8FqYuLg4FOTewC667Dy_jEgRSdgPyTS2Ih4hujW50PDZ-GGXvkCdYm6w"}}},"title":"SpotX-Linux/install.sh at main · SpotX-CLI/SpotX-Linux","locale":"en","appPayload":{"helpUrl":"https://docs.github.com","findFileWorkerPath":"/assets-cdn/worker/find-file-worker-848bb9a5da17.js","findInFileWorkerPath":"/assets-cdn/worker/find-in-file-worker-8812f8040df6.js","githubDevUrl":"https://github.dev/","enabled_features":{"virtualize_file_tree":true,"react_repos_overview":false,"repos_new_shortcut_enabled":false,"blob_navigation_cursor":true,"code_nav_ui_events":false,"ref_selector_v2":false,"codeview_codemirror_next":false}}}</script>
  <div data-target="react-app.reactRoot"><div color="fg.default" font-family="normal" data-portal-root="true" class="BaseStyles__Base-sc-nfjs56-0 cRXyfx"><div id="__primerPortalRoot__" style="z-index: 10; position: absolute; width: 100%;"></div><meta data-hydrostats="publish">    <button data-testid="header-permalink-button" data-hotkey="y,Y" data-hotkey-scope="read-only-cursor-text-area" hidden=""></button><button data-hotkey="y,Y" hidden=""></button><div class="Box-sc-g0xbh4-0"><div style="--sticky-pane-height: calc(100vh - (max(174px, 0px)));" class="Box-sc-g0xbh4-0 fSWWem"><div class="Box-sc-g0xbh4-0 kPPmzM"><div class="Box-sc-g0xbh4-0 cIAPDV"><div tabindex="0" class="Box-sc-g0xbh4-0 gvCnwW"><div class="Box-sc-g0xbh4-0 ioxSsX"><div class="Box-sc-g0xbh4-0 eUyHuk"></div><div class="Box-sc-g0xbh4-0 gCWmGY"><div role="separator" class="Box-sc-g0xbh4-0 gAHDJQ"></div></div><div style="--pane-width: 320px;" class="Box-sc-g0xbh4-0 gNdDUH"><span class="_VisuallyHidden__VisuallyHidden-sc-11jhm7a-0 rTZSs"><form><label for=":r0:-width-input">Pane width</label><p id=":r0:-input-hint">Use a value between 18% and 33%</p><input id=":r0:-width-input" aria-describedby=":r0:-input-hint" name="pane-width" inputmode="numeric" pattern="[0-9]*" autocorrect="off" autocomplete="off" type="text" value="22"><button type="submit">Change width</button></form></span><div id="repos-file-tree" class="Box-sc-g0xbh4-0 dkMzXD"><div class="Box-sc-g0xbh4-0 hBSSUC"><div class="Box-sc-g0xbh4-0 iPurHz"><h2 class="Heading__StyledHeading-sc-1c1dgg0-0 fNPcqd"><button data-component="IconButton" data-testid="collapse-file-tree-button" aria-label="Side panel" aria-expanded="true" aria-controls="repos-file-tree" class="types__StyledButton-sc-ws60qy-0 hiLVSC" data-no-visuals="true"><svg aria-hidden="true" focusable="false" role="img" class="octicon octicon-sidebar-expand" viewBox="0 0 16 16" width="16" height="16" fill="currentColor" style="display: inline-block; user-select: none; vertical-align: text-bottom; overflow: visible;"><path d="m4.177 7.823 2.396-2.396A.25.25 0 0 1 7 5.604v4.792a.25.25 0 0 1-.427.177L4.177 8.177a.25.25 0 0 1 0-.354Z"></path><path d="M0 1.75C0 .784.784 0 1.75 0h12.5C15.216 0 16 .784 16 1.75v12.5A1.75 1.75 0 0 1 14.25 16H1.75A1.75 1.75 0 0 1 0 14.25Zm1.75-.25a.25.25 0 0 0-.25.25v12.5c0 .138.112.25.25.25H9.5v-13Zm12.5 13a.25.25 0 0 0 .25-.25V1.75a.25.25 0 0 0-.25-.25H11v13Z"></path></svg></button></h2><h2 class="Heading__StyledHeading-sc-1c1dgg0-0 imcwCi">Code</h2></div><div class="Box-sc-g0xbh4-0 hVHHYa"><div class="Box-sc-g0xbh4-0 idZfsJ"><button type="button" id="branch-picker-1685363925510" aria-haspopup="true" tabindex="0" data-hotkey="w" aria-label="main branch" data-testid="anchor-button" class="types__StyledButton-sc-ws60qy-0 gkElr react-repos-tree-pane-ref-selector width-full"><span data-component="buttonContent" class="Box-sc-g0xbh4-0 kkrdEu"><span data-component="text"><div class="Box-sc-g0xbh4-0 cFPoqW"><div class="Box-sc-g0xbh4-0 dAmgfA"><svg aria-hidden="true" focusable="false" role="img" class="octicon octicon-git-branch" viewBox="0 0 16 16" width="16" height="16" fill="currentColor" style="display: inline-block; user-select: none; vertical-align: text-bottom; overflow: visible;"><path d="M9.5 3.25a2.25 2.25 0 1 1 3 2.122V6A2.5 2.5 0 0 1 10 8.5H6a1 1 0 0 0-1 1v1.128a2.251 2.251 0 1 1-1.5 0V5.372a2.25 2.25 0 1 1 1.5 0v1.836A2.493 2.493 0 0 1 6 7h4a1 1 0 0 0 1-1v-.628A2.25 2.25 0 0 1 9.5 3.25Zm-6 0a.75.75 0 1 0 1.5 0 .75.75 0 0 0-1.5 0Zm8.25-.75a.75.75 0 1 0 0 1.5.75.75 0 0 0 0-1.5ZM4.25 12a.75.75 0 1 0 0 1.5.75.75 0 0 0 0-1.5Z"></path></svg></div><div class="Box-sc-g0xbh4-0 caeYDk"><span class="Text-sc-17v1xeu-0 bOMzPg">&nbsp;main</span></div></div></span><span data-component="trailingVisual" class="Box-sc-g0xbh4-0 trpoQ"><svg aria-hidden="true" focusable="false" role="img" class="octicon octicon-triangle-down" viewBox="0 0 16 16" width="16" height="16" fill="currentColor" style="display: inline-block; user-select: none; vertical-align: text-bottom; overflow: visible;"><path d="m4.427 7.427 3.396 3.396a.25.25 0 0 0 .354 0l3.396-3.396A.25.25 0 0 0 11.396 7H4.604a.25.25 0 0 0-.177.427Z"></path></svg></span></span></button><button data-hotkey="w" data-hotkey-scope="read-only-cursor-text-area" hidden=""></button></div><span role="tooltip" aria-label="Add file" class="Tooltip__TooltipBase-sc-uha8qm-0 cogBOk tooltipped-s"><a sx="[object Object]" data-component="IconButton" aria-label="Add file" data-no-visuals="true" class="types__StyledButton-sc-ws60qy-0 gACNhT" href="https://github.com/SpotX-CLI/SpotX-Linux/new/main"><svg aria-hidden="true" focusable="false" role="img" class="octicon octicon-plus" viewBox="0 0 16 16" width="16" height="16" fill="currentColor" style="display: inline-block; user-select: none; vertical-align: text-bottom; overflow: visible;"><path d="M7.75 2a.75.75 0 0 1 .75.75V7h4.25a.75.75 0 0 1 0 1.5H8.5v4.25a.75.75 0 0 1-1.5 0V8.5H2.75a.75.75 0 0 1 0-1.5H7V2.75A.75.75 0 0 1 7.75 2Z"></path></svg></a></span><button data-component="IconButton" aria-label="Search this repository" data-hotkey="/" data-no-visuals="true" class="types__StyledButton-sc-ws60qy-0 fOLLjc"><svg aria-hidden="true" focusable="false" role="img" class="octicon octicon-search" viewBox="0 0 16 16" width="16" height="16" fill="currentColor" style="display: inline-block; user-select: none; vertical-align: text-bottom; overflow: visible;"><path d="M10.68 11.74a6 6 0 0 1-7.922-8.982 6 6 0 0 1 8.982 7.922l3.04 3.04a.749.749 0 0 1-.326 1.275.749.749 0 0 1-.734-.215ZM11.5 7a4.499 4.499 0 1 0-8.997 0A4.499 4.499 0 0 0 11.5 7Z"></path></svg></button><button data-testid="" data-hotkey="/" data-hotkey-scope="read-only-cursor-text-area" hidden=""></button></div></div><div class="Box-sc-g0xbh4-0 jRttMj"><button data-testid="" data-hotkey="t,T" data-hotkey-scope="read-only-cursor-text-area" hidden=""></button><button data-hotkey="t,T" hidden=""></button><span class="_TextInputWrapper__TextInputBaseWrapper-sc-apywy2-0 _TextInputWrapper__TextInputWrapper-sc-apywy2-1 bMghX jYmabv TextInput-wrapper" aria-live="polite" aria-busy="false"><span class="TextInput-icon"><svg aria-hidden="true" focusable="false" role="img" class="octicon octicon-search" viewBox="0 0 16 16" width="16" height="16" fill="currentColor" style="display: inline-block; user-select: none; vertical-align: text-bottom; overflow: visible;"><path d="M10.68 11.74a6 6 0 0 1-7.922-8.982 6 6 0 0 1 8.982 7.922l3.04 3.04a.749.749 0 0 1-.326 1.275.749.749 0 0 1-.734-.215ZM11.5 7a4.499 4.499 0 1 0-8.997 0A4.499 4.499 0 0 0 11.5 7Z"></path></svg></span><input type="text" aria-label="Go to file" role="combobox" aria-controls="file-results-list" aria-expanded="false" aria-haspopup="dialog" autocorrect="off" spellcheck="false" placeholder="Go to file" data-component="input" class="_UnstyledTextInput__UnstyledTextInput-sc-31b2um-0 dFGJZq"><span class="TextInput-icon"><div class="Box-sc-g0xbh4-0 cNvKlH"><kbd>t</kbd></div></span></span></div><div class="Box-sc-g0xbh4-0 bYLCoz"><div><div data-testid="repos-file-tree-container" class="Box-sc-g0xbh4-0 hJcmjJ"><nav aria-label="File Tree Navigation"><span role="status" aria-live="polite" aria-atomic="true" class="_VisuallyHidden__VisuallyHidden-sc-11jhm7a-0 rTZSs"></span><ul role="tree" aria-label="Files" class="TreeView__UlBox-sc-4ex6b6-0 kUIgyV"><li class="PRIVATE_TreeView-item" tabindex="0" id=".github-item" role="treeitem" aria-labelledby=":r6:" aria-describedby=":r7: :r8:" aria-level="1" aria-expanded="false" aria-selected="false"><div class="PRIVATE_TreeView-item-container" style="--level: 1; contain-intrinsic-size: auto 2rem;"><div style="grid-area: spacer; display: flex;"><div style="width: 100%; display: flex;"></div></div><div class="PRIVATE_TreeView-item-toggle PRIVATE_TreeView-item-toggle--hover PRIVATE_TreeView-item-toggle--end"><svg aria-hidden="true" focusable="false" role="img" class="octicon octicon-chevron-right" viewBox="0 0 12 12" width="12" height="12" fill="currentColor" style="display: inline-block; user-select: none; vertical-align: text-bottom; overflow: visible;"><path d="M4.7 10c-.2 0-.4-.1-.5-.2-.3-.3-.3-.8 0-1.1L6.9 6 4.2 3.3c-.3-.3-.3-.8 0-1.1.3-.3.8-.3 1.1 0l3.3 3.2c.3.3.3.8 0 1.1L5.3 9.7c-.2.2-.4.3-.6.3Z"></path></svg></div><div id=":r6:" class="PRIVATE_TreeView-item-content"><div class="PRIVATE_VisuallyHidden" aria-hidden="true" id=":r7:"></div><div class="PRIVATE_TreeView-item-visual" aria-hidden="true"><div class="PRIVATE_TreeView-directory-icon"><svg aria-hidden="true" focusable="false" role="img" class="octicon octicon-file-directory-fill" viewBox="0 0 16 16" width="16" height="16" fill="currentColor" style="display: inline-block; user-select: none; vertical-align: text-bottom; overflow: visible;"><path d="M1.75 1A1.75 1.75 0 0 0 0 2.75v10.5C0 14.216.784 15 1.75 15h12.5A1.75 1.75 0 0 0 16 13.25v-8.5A1.75 1.75 0 0 0 14.25 3H7.5a.25.25 0 0 1-.2-.1l-.9-1.2C6.07 1.26 5.55 1 5 1H1.75Z"></path></svg></div></div><span class="PRIVATE_TreeView-item-content-text"><span>.github</span></span></div></div></li><li class="PRIVATE_TreeView-item" tabindex="-1" id="LICENSE-item" role="treeitem" aria-labelledby=":r9:" aria-describedby=":ra: :rb:" aria-level="1" aria-selected="false"><div class="PRIVATE_TreeView-item-container" style="--level: 1; contain-intrinsic-size: auto 2rem;"><div style="grid-area: spacer; display: flex;"><div style="width: 100%; display: flex;"></div></div><div id=":r9:" class="PRIVATE_TreeView-item-content"><div class="PRIVATE_VisuallyHidden" aria-hidden="true" id=":ra:"></div><div class="PRIVATE_TreeView-item-visual" aria-hidden="true"><svg aria-hidden="true" focusable="false" role="img" class="octicon octicon-file" viewBox="0 0 16 16" width="16" height="16" fill="currentColor" style="display: inline-block; user-select: none; vertical-align: text-bottom; overflow: visible;"><path d="M2 1.75C2 .784 2.784 0 3.75 0h6.586c.464 0 .909.184 1.237.513l2.914 2.914c.329.328.513.773.513 1.237v9.586A1.75 1.75 0 0 1 13.25 16h-9.5A1.75 1.75 0 0 1 2 14.25Zm1.75-.25a.25.25 0 0 0-.25.25v12.5c0 .138.112.25.25.25h9.5a.25.25 0 0 0 .25-.25V6h-2.75A1.75 1.75 0 0 1 9 4.25V1.5Zm6.75.062V4.25c0 .138.112.25.25.25h2.688l-.011-.013-2.914-2.914-.013-.011Z"></path></svg></div><span class="PRIVATE_TreeView-item-content-text"><span>LICENSE</span></span></div></div></li><li class="PRIVATE_TreeView-item" tabindex="-1" id="install.sh-item" role="treeitem" aria-labelledby=":rc:" aria-describedby=":rd: :re:" aria-level="1" aria-current="true" aria-selected="false"><div class="PRIVATE_TreeView-item-container" style="--level: 1; contain-intrinsic-size: auto 2rem;"><div style="grid-area: spacer; display: flex;"><div style="width: 100%; display: flex;"></div></div><div id=":rc:" class="PRIVATE_TreeView-item-content"><div class="PRIVATE_VisuallyHidden" aria-hidden="true" id=":rd:"></div><div class="PRIVATE_TreeView-item-visual" aria-hidden="true"><svg aria-hidden="true" focusable="false" role="img" class="octicon octicon-file" viewBox="0 0 16 16" width="16" height="16" fill="currentColor" style="display: inline-block; user-select: none; vertical-align: text-bottom; overflow: visible;"><path d="M2 1.75C2 .784 2.784 0 3.75 0h6.586c.464 0 .909.184 1.237.513l2.914 2.914c.329.328.513.773.513 1.237v9.586A1.75 1.75 0 0 1 13.25 16h-9.5A1.75 1.75 0 0 1 2 14.25Zm1.75-.25a.25.25 0 0 0-.25.25v12.5c0 .138.112.25.25.25h9.5a.25.25 0 0 0 .25-.25V6h-2.75A1.75 1.75 0 0 1 9 4.25V1.5Zm6.75.062V4.25c0 .138.112.25.25.25h2.688l-.011-.013-2.914-2.914-.013-.011Z"></path></svg></div><span class="PRIVATE_TreeView-item-content-text"><span>install.sh</span></span></div></div></li><li class="PRIVATE_TreeView-item" tabindex="-1" id="readme.md-item" role="treeitem" aria-labelledby=":rf:" aria-describedby=":rg: :rh:" aria-level="1" aria-selected="false"><div class="PRIVATE_TreeView-item-container" style="--level: 1; contain-intrinsic-size: auto 2rem;"><div style="grid-area: spacer; display: flex;"><div style="width: 100%; display: flex;"></div></div><div id=":rf:" class="PRIVATE_TreeView-item-content"><div class="PRIVATE_VisuallyHidden" aria-hidden="true" id=":rg:"></div><div class="PRIVATE_TreeView-item-visual" aria-hidden="true"><svg aria-hidden="true" focusable="false" role="img" class="octicon octicon-file" viewBox="0 0 16 16" width="16" height="16" fill="currentColor" style="display: inline-block; user-select: none; vertical-align: text-bottom; overflow: visible;"><path d="M2 1.75C2 .784 2.784 0 3.75 0h6.586c.464 0 .909.184 1.237.513l2.914 2.914c.329.328.513.773.513 1.237v9.586A1.75 1.75 0 0 1 13.25 16h-9.5A1.75 1.75 0 0 1 2 14.25Zm1.75-.25a.25.25 0 0 0-.25.25v12.5c0 .138.112.25.25.25h9.5a.25.25 0 0 0 .25-.25V6h-2.75A1.75 1.75 0 0 1 9 4.25V1.5Zm6.75.062V4.25c0 .138.112.25.25.25h2.688l-.011-.013-2.914-2.914-.013-.011Z"></path></svg></div><span class="PRIVATE_TreeView-item-content-text"><span>readme.md</span></span></div></div></li><li class="PRIVATE_TreeView-item" tabindex="-1" id="uninstall.sh-item" role="treeitem" aria-labelledby=":ri:" aria-describedby=":rj: :rk:" aria-level="1" aria-selected="false"><div class="PRIVATE_TreeView-item-container" style="--level: 1; contain-intrinsic-size: auto 2rem;"><div style="grid-area: spacer; display: flex;"><div style="width: 100%; display: flex;"></div></div><div id=":ri:" class="PRIVATE_TreeView-item-content"><div class="PRIVATE_VisuallyHidden" aria-hidden="true" id=":rj:"></div><div class="PRIVATE_TreeView-item-visual" aria-hidden="true"><svg aria-hidden="true" focusable="false" role="img" class="octicon octicon-file" viewBox="0 0 16 16" width="16" height="16" fill="currentColor" style="display: inline-block; user-select: none; vertical-align: text-bottom; overflow: visible;"><path d="M2 1.75C2 .784 2.784 0 3.75 0h6.586c.464 0 .909.184 1.237.513l2.914 2.914c.329.328.513.773.513 1.237v9.586A1.75 1.75 0 0 1 13.25 16h-9.5A1.75 1.75 0 0 1 2 14.25Zm1.75-.25a.25.25 0 0 0-.25.25v12.5c0 .138.112.25.25.25h9.5a.25.25 0 0 0 .25-.25V6h-2.75A1.75 1.75 0 0 1 9 4.25V1.5Zm6.75.062V4.25c0 .138.112.25.25.25h2.688l-.011-.013-2.914-2.914-.013-.011Z"></path></svg></div><span class="PRIVATE_TreeView-item-content-text"><span>uninstall.sh</span></span></div></div></li></ul></nav></div></div><div class="Box-sc-g0xbh4-0 hwhShM"><div class="Box-sc-g0xbh4-0 cYPxpP"><a href="https://docs.github.com/en/repositories/working-with-files/managing-files/navigating-files-with-the-new-code-view" target="_blank" class="Link__StyledLink-sc-14289xe-0 eKGBQn">Documentation</a>&nbsp;•&nbsp;<a href="https://github.com/orgs/community/discussions/54546" target="_blank" class="Link__StyledLink-sc-14289xe-0 eKGBQn">Share feedback</a></div></div></div><div class="Box-sc-g0xbh4-0 fBtiVT"><div class="Box-sc-g0xbh4-0 cYPxpP"><a href="https://docs.github.com/en/repositories/working-with-files/managing-files/navigating-files-with-the-new-code-view" target="_blank" class="Link__StyledLink-sc-14289xe-0 eKGBQn">Documentation</a>&nbsp;•&nbsp;<a href="https://github.com/orgs/community/discussions/54546" target="_blank" class="Link__StyledLink-sc-14289xe-0 eKGBQn">Share feedback</a></div></div></div></div></div></div><main class="Box-sc-g0xbh4-0 emFMJu"><div class="Box-sc-g0xbh4-0"></div><div class="Box-sc-g0xbh4-0 hlUAHL"><div data-selector="repos-split-pane-content" tabindex="0" class="Box-sc-g0xbh4-0 iStsmI"><div class="Box-sc-g0xbh4-0 eIgvIk"><div id="StickyHeader" class="Box-sc-g0xbh4-0 bDwCYs"><div class="Box-sc-g0xbh4-0 rmFvl"><div class="Box-sc-g0xbh4-0 dyczTK"><div class="Box-sc-g0xbh4-0 jJaodr"><div class="Box-sc-g0xbh4-0 eTvGbF"><nav data-testid="breadcrumbs" aria-labelledby="breadcrumb-heading" id="breadcrumb" class="Box-sc-g0xbh4-0 kzRgrI"><h2 class="Heading__StyledHeading-sc-1c1dgg0-0 cgQnMS sr-only" data-testid="screen-reader-heading" id="breadcrumb-heading">Breadcrumbs</h2><ol class="Box-sc-g0xbh4-0 cmAPIB"><li class="Box-sc-g0xbh4-0 jwXCBK"><a sx="[object Object]" data-testid="breadcrumbs-repo-link" class="Link__StyledLink-sc-14289xe-0 JtPvy" href="https://github.com/SpotX-CLI/SpotX-Linux/tree/main">SpotX-Linux</a></li></ol></nav><div data-testid="breadcrumbs-filename" class="Box-sc-g0xbh4-0 jwXCBK"><span aria-hidden="true" class="Text-sc-17v1xeu-0 wVyhN">/</span><h1 tabindex="-1" id="file-name-id" class="Heading__StyledHeading-sc-1c1dgg0-0 diwsLq">install.sh</h1></div><button data-component="IconButton" aria-label="Copy path" data-testid="breadcrumb-copy-path-button" data-size="small" data-no-visuals="true" class="types__StyledButton-sc-ws60qy-0 cisIM"><svg aria-hidden="true" focusable="false" role="img" class="octicon octicon-copy" viewBox="0 0 16 16" width="16" height="16" fill="currentColor" style="display: inline-block; user-select: none; vertical-align: text-bottom; overflow: visible;"><path d="M0 6.75C0 5.784.784 5 1.75 5h1.5a.75.75 0 0 1 0 1.5h-1.5a.25.25 0 0 0-.25.25v7.5c0 .138.112.25.25.25h7.5a.25.25 0 0 0 .25-.25v-1.5a.75.75 0 0 1 1.5 0v1.5A1.75 1.75 0 0 1 9.25 16h-7.5A1.75 1.75 0 0 1 0 14.25Z"></path><path d="M5 1.75C5 .784 5.784 0 6.75 0h7.5C15.216 0 16 .784 16 1.75v7.5A1.75 1.75 0 0 1 14.25 11h-7.5A1.75 1.75 0 0 1 5 9.25Zm1.75-.25a.25.25 0 0 0-.25.25v7.5c0 .138.112.25.25.25h7.5a.25.25 0 0 0 .25-.25v-7.5a.25.25 0 0 0-.25-.25Z"></path></svg></button></div></div><div class="Box-sc-g0xbh4-0 gtBUEp"><div class="d-flex gap-2"> <button data-testid="" data-hotkey="l,L" data-hotkey-scope="read-only-cursor-text-area" hidden=""></button><button data-hotkey="l,L" hidden=""></button><button data-testid="" data-hotkey="Control+g" data-hotkey-scope="read-only-cursor-text-area" hidden=""></button><button data-hotkey="Control+g" hidden=""></button><button type="button" data-hotkey="b,B" data-no-visuals="true" class="types__StyledButton-sc-ws60qy-0 eQDZir"><span data-component="buttonContent" class="Box-sc-g0xbh4-0 kkrdEu"><span data-component="text">Blame</span></span></button><button data-testid="" data-hotkey="b,B" data-hotkey-scope="read-only-cursor-text-area" hidden=""></button><button data-component="IconButton" aria-label="More file actions" class="types__StyledButton-sc-ws60qy-0 kUdakW js-blob-dropdown-click" title="More file actions" data-testid="more-file-actions-button" id=":r3:" aria-haspopup="true" tabindex="0" data-no-visuals="true"><svg aria-hidden="true" focusable="false" role="img" class="octicon octicon-kebab-horizontal" viewBox="0 0 16 16" width="16" height="16" fill="currentColor" style="display: inline-block; user-select: none; vertical-align: text-bottom; overflow: visible;"><path d="M8 9a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3ZM1.5 9a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3Zm13 0a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3Z"></path></svg></button> </div></div></div></div></div></div><div class="Box-sc-g0xbh4-0 bhAUGf"> <div class="Box-sc-g0xbh4-0 cMYnca"></div><div class="Box-sc-g0xbh4-0"></div>   </div><div class="Box-sc-g0xbh4-0 fwKaNR">   <button data-testid="" data-hotkey="r,R" data-hotkey-scope="read-only-cursor-text-area" hidden=""></button><button data-hotkey="r,R" hidden=""></button><div class="Box-sc-g0xbh4-0 gSaHsc"><div class="Box-sc-g0xbh4-0 eYedVD"><h2 class="Heading__StyledHeading-sc-1c1dgg0-0 cgQnMS sr-only" data-testid="screen-reader-heading">Latest commit</h2><div data-testid="latest-commit" class="Box-sc-g0xbh4-0 ihByZp"><div class="Box-sc-g0xbh4-0 hLLhje"><a href="https://github.com/jetfir3" data-testid="avatar-icon-link" data-hovercard-url="/users/jetfir3/hovercard" class="Link__StyledLink-sc-14289xe-0 eKGBQn"><img aria-label="jetfir3" src="Spotify_Linux_files/95306468.png" alt="jetfir3" size="20" class="Avatar-sc-2lv0r8-0 kNkJaw" width="20" height="20"></a><span role="tooltip" aria-label="commits by jetfir3" class="Tooltip__TooltipBase-sc-uha8qm-0 cogBOk tooltipped-se"><a href="https://github.com/SpotX-CLI/SpotX-Linux/commits?author=jetfir3" aria-label="commits by jetfir3" class="Link__StyledLink-sc-14289xe-0 kQZlNi">jetfir3</a></span></div><div class="Box-sc-g0xbh4-0 fqNQBl react-last-commit-message"><div class="Box-sc-g0xbh4-0 jEKUjt Truncate"><span class="Text-sc-17v1xeu-0 gPDEWA Truncate-text" data-testid="latest-commit-html"><a href="https://github.com/SpotX-CLI/SpotX-Linux/commit/655bf3fd55f36ae447561640e396068932d17ae3" class="Link--secondary" title="1.2.3.1115 bringup (#28)

- removed home2 patch for v1.2.3+ clients
- disabled `exclude` flag, left sidebar is now considered stable when using new UI. 
- fixed typos" data-pjax="true" data-hovercard-url="/SpotX-CLI/SpotX-Linux/commit/655bf3fd55f36ae447561640e396068932d17ae3/hovercard">1.2.3.1115 bringup (</a><a href="https://github.com/SpotX-CLI/SpotX-Linux/pull/28" data-hovercard-url="/SpotX-CLI/SpotX-Linux/pull/28/hovercard" data-hovercard-type="pull_request" data-url="https://github.com/SpotX-CLI/SpotX-Linux/issues/28" data-permission-text="Title is private" data-id="1551229785" data-error-text="Failed to load title" class="issue-link js-issue-link">#28</a><a href="https://github.com/SpotX-CLI/SpotX-Linux/commit/655bf3fd55f36ae447561640e396068932d17ae3" class="Link--secondary" title="1.2.3.1115 bringup (#28)

- removed home2 patch for v1.2.3+ clients
- disabled `exclude` flag, left sidebar is now considered stable when using new UI. 
- fixed typos" data-pjax="true" data-hovercard-url="/SpotX-CLI/SpotX-Linux/commit/655bf3fd55f36ae447561640e396068932d17ae3/hovercard">)</a></span></div><button data-component="IconButton" aria-label="Open commit details" aria-pressed="false" aria-expanded="false" data-testid="latest-commit-details-toggle" data-size="small" data-no-visuals="true" class="types__StyledButton-sc-ws60qy-0 fnONpD"><svg aria-hidden="true" focusable="false" role="img" class="octicon octicon-ellipsis" viewBox="0 0 16 16" width="16" height="16" fill="currentColor" style="display: inline-block; user-select: none; vertical-align: text-bottom; overflow: visible;"><path d="M0 5.75C0 4.784.784 4 1.75 4h12.5c.966 0 1.75.784 1.75 1.75v4.5A1.75 1.75 0 0 1 14.25 12H1.75A1.75 1.75 0 0 1 0 10.25ZM12 7a1 1 0 1 0 0 2 1 1 0 0 0 0-2ZM7 8a1 1 0 1 0 2 0 1 1 0 0 0-2 0ZM4 7a1 1 0 1 0 0 2 1 1 0 0 0 0-2Z"></path></svg></button><div class="Box-sc-g0xbh4-0"><button data-component="IconButton" data-testid="checks-status-badge-icon" aria-label="success" data-size="small" data-no-visuals="true" class="types__StyledButton-sc-ws60qy-0 dQqUwP"><svg aria-hidden="true" focusable="false" role="img" class="octicon octicon-check" viewBox="0 0 16 16" width="16" height="16" fill="currentColor" style="display: inline-block; user-select: none; vertical-align: text-bottom; overflow: visible;"><path d="M13.78 4.22a.75.75 0 0 1 0 1.06l-7.25 7.25a.75.75 0 0 1-1.06 0L2.22 9.28a.751.751 0 0 1 .018-1.042.751.751 0 0 1 1.042-.018L6 10.94l6.72-6.72a.75.75 0 0 1 1.06 0Z"></path></svg></button></div></div><span class="Text-sc-17v1xeu-0 gmaYYF react-last-commit-summary-timestamp"><relative-time class="RelativeTime-sc-lqbqy3-0" datetime="2023-01-20T12:57:14.000-05:00" tense="past" title="Jan 20, 2023, 5:57 PM GMT"></relative-time></span></div><div class="Box-sc-g0xbh4-0 jGfYmh"><div data-testid="latest-commit-details" class="Box-sc-g0xbh4-0 lhFvfi"><span class="Text-sc-17v1xeu-0 gmaYYF react-last-commit-oid-timestamp"><a class="Link__StyledLink-sc-14289xe-0 eKGBQn Link--secondary" aria-label="Commit 655bf3f" href="https://github.com/SpotX-CLI/SpotX-Linux/commit/655bf3fd55f36ae447561640e396068932d17ae3">655bf3f</a>&nbsp;·&nbsp;<relative-time class="RelativeTime-sc-lqbqy3-0" datetime="2023-01-20T12:57:14.000-05:00" tense="past" title="Jan 20, 2023, 5:57 PM GMT"></relative-time></span><span class="Text-sc-17v1xeu-0 gmaYYF react-last-commit-timestamp"><relative-time class="RelativeTime-sc-lqbqy3-0" datetime="2023-01-20T12:57:14.000-05:00" tense="past" title="Jan 20, 2023, 5:57 PM GMT"></relative-time></span></div><h2 class="Heading__StyledHeading-sc-1c1dgg0-0 cgQnMS sr-only" data-testid="screen-reader-heading">History</h2><a aria-label="History" class="types__StyledButton-sc-ws60qy-0 GSmVB react-last-commit-history-group" href="https://github.com/SpotX-CLI/SpotX-Linux/commits/main/install.sh" data-size="small"><span data-component="buttonContent" class="Box-sc-g0xbh4-0 kkrdEu"><span data-component="leadingVisual" class="Box-sc-g0xbh4-0 trpoQ"><svg aria-hidden="true" focusable="false" role="img" class="octicon octicon-history" viewBox="0 0 16 16" width="16" height="16" fill="currentColor" style="display: inline-block; user-select: none; vertical-align: text-bottom; overflow: visible;"><path d="m.427 1.927 1.215 1.215a8.002 8.002 0 1 1-1.6 5.685.75.75 0 1 1 1.493-.154 6.5 6.5 0 1 0 1.18-4.458l1.358 1.358A.25.25 0 0 1 3.896 6H.25A.25.25 0 0 1 0 5.75V2.104a.25.25 0 0 1 .427-.177ZM7.75 4a.75.75 0 0 1 .75.75v2.992l2.028.812a.75.75 0 0 1-.557 1.392l-2.5-1A.751.751 0 0 1 7 8.25v-3.5A.75.75 0 0 1 7.75 4Z"></path></svg></span><span data-component="text"><span class="Text-sc-17v1xeu-0 irdYzI">History</span></span></span></a><div class="Box-sc-g0xbh4-0 bqgLjk"><button data-component="IconButton" aria-label="Open commit details" aria-pressed="false" aria-expanded="false" data-testid="latest-commit-details-toggle" data-no-visuals="true" class="types__StyledButton-sc-ws60qy-0 hfwSZj"><svg aria-hidden="true" focusable="false" role="img" class="octicon octicon-ellipsis" viewBox="0 0 16 16" width="16" height="16" fill="currentColor" style="display: inline-block; user-select: none; vertical-align: text-bottom; overflow: visible;"><path d="M0 5.75C0 4.784.784 4 1.75 4h12.5c.966 0 1.75.784 1.75 1.75v4.5A1.75 1.75 0 0 1 14.25 12H1.75A1.75 1.75 0 0 1 0 10.25ZM12 7a1 1 0 1 0 0 2 1 1 0 0 0 0-2ZM7 8a1 1 0 1 0 2 0 1 1 0 0 0-2 0ZM4 7a1 1 0 1 0 0 2 1 1 0 0 0 0-2Z"></path></svg></button></div><a aria-label="History" class="types__StyledButton-sc-ws60qy-0 GSmVB react-last-commit-history-icon" href="https://github.com/SpotX-CLI/SpotX-Linux/commits/main/install.sh"><span data-component="buttonContent" class="Box-sc-g0xbh4-0 kkrdEu"><span data-component="leadingVisual" class="Box-sc-g0xbh4-0 trpoQ"><svg aria-hidden="true" focusable="false" role="img" class="octicon octicon-history" viewBox="0 0 16 16" width="16" height="16" fill="currentColor" style="display: inline-block; user-select: none; vertical-align: text-bottom; overflow: visible;"><path d="m.427 1.927 1.215 1.215a8.002 8.002 0 1 1-1.6 5.685.75.75 0 1 1 1.493-.154 6.5 6.5 0 1 0 1.18-4.458l1.358 1.358A.25.25 0 0 1 3.896 6H.25A.25.25 0 0 1 0 5.75V2.104a.25.25 0 0 1 .427-.177ZM7.75 4a.75.75 0 0 1 .75.75v2.992l2.028.812a.75.75 0 0 1-.557 1.392l-2.5-1A.751.751 0 0 1 7 8.25v-3.5A.75.75 0 0 1 7.75 4Z"></path></svg></span></span></a></div></div></div><div class="Box-sc-g0xbh4-0 bSdwWB react-code-size-details-banner"><div class="Box-sc-g0xbh4-0 react-code-size-details-banner"><div class="Box-sc-g0xbh4-0 hCJWbg text-mono"><div title="18.7 KB" data-testid="blob-size" class="Truncate-sc-1d9305p-0 Jyrkr"><span class="Text-sc-17v1xeu-0 gPDEWA">339 lines (305 loc) · 18.7 KB</span></div></div></div></div><div class="Box-sc-g0xbh4-0 izfgQu"><div class="Box-sc-g0xbh4-0 cQgThc"><div class="Box-sc-g0xbh4-0 gBKNLX react-blob-view-header-sticky" id="repos-sticky-header"><div class="Box-sc-g0xbh4-0"><div class="Box-sc-g0xbh4-0 ePiodO"><div class="Box-sc-g0xbh4-0 kQJlnf"><div class="Box-sc-g0xbh4-0 gJICKO"><div class="Box-sc-g0xbh4-0 iZJewz"><nav data-testid="breadcrumbs" aria-labelledby="sticky-breadcrumb-heading" id="sticky-breadcrumb" class="Box-sc-g0xbh4-0 kzRgrI"><h2 class="Heading__StyledHeading-sc-1c1dgg0-0 cgQnMS sr-only" data-testid="screen-reader-heading" id="sticky-breadcrumb-heading">Breadcrumbs</h2><ol class="Box-sc-g0xbh4-0 cmAPIB"><li class="Box-sc-g0xbh4-0 jwXCBK"><a sx="[object Object]" data-testid="breadcrumbs-repo-link" class="Link__StyledLink-sc-14289xe-0 JtPvy" href="https://github.com/SpotX-CLI/SpotX-Linux/tree/main">SpotX-Linux</a></li></ol></nav><div data-testid="breadcrumbs-filename" class="Box-sc-g0xbh4-0 jwXCBK"><span aria-hidden="true" class="Text-sc-17v1xeu-0 dqiNLD">/</span><h1 tabindex="-1" id="sticky-file-name-id" class="Heading__StyledHeading-sc-1c1dgg0-0 jAEDJk">install.sh</h1></div></div><button type="button" data-size="small" class="types__StyledButton-sc-ws60qy-0 gyejuL"><span data-component="buttonContent" class="Box-sc-g0xbh4-0 kkrdEu"><span data-component="leadingVisual" class="Box-sc-g0xbh4-0 trpoQ"><svg aria-hidden="true" focusable="false" role="img" class="octicon octicon-arrow-up" viewBox="0 0 16 16" width="16" height="16" fill="currentColor" style="display: inline-block; user-select: none; vertical-align: text-bottom; overflow: visible;"><path d="M3.47 7.78a.75.75 0 0 1 0-1.06l4.25-4.25a.75.75 0 0 1 1.06 0l4.25 4.25a.751.751 0 0 1-.018 1.042.751.751 0 0 1-1.042.018L9 4.81v7.44a.75.75 0 0 1-1.5 0V4.81L4.53 7.78a.75.75 0 0 1-1.06 0Z"></path></svg></span><span data-component="text">Top</span></span></button></div></div><div class="Box-sc-g0xbh4-0 dhOLuh"><h2 class="Heading__StyledHeading-sc-1c1dgg0-0 cgQnMS sr-only" data-testid="screen-reader-heading">File metadata and controls</h2><div class="Box-sc-g0xbh4-0 bfkNRF"><ul aria-label="File view" class="SegmentedControl__SegmentedControlList-sc-1rzig82-0 pdqXX"><li class="Box-sc-g0xbh4-0 fXBLEV"><button aria-current="true" class="SegmentedControlButton__SegmentedControlButtonStyled-sc-8lkgxl-0 jsofOr"><span class="segmentedControl-content"><div class="Box-sc-g0xbh4-0 segmentedControl-text">Code</div></span></button></li><li class="Box-sc-g0xbh4-0 hBnzlN"><button aria-current="false" data-hotkey="b,B" class="SegmentedControlButton__SegmentedControlButtonStyled-sc-8lkgxl-0 beHpEz"><span class="segmentedControl-content"><div class="Box-sc-g0xbh4-0 segmentedControl-text">Blame</div></span></button></li></ul><button data-testid="" data-hotkey-scope="read-only-cursor-text-area" hidden=""></button><button data-testid="" data-hotkey="b,B" data-hotkey-scope="read-only-cursor-text-area" hidden=""></button><button data-testid="" data-hotkey-scope="read-only-cursor-text-area" hidden=""></button><div class="Box-sc-g0xbh4-0 react-code-size-details-in-header"><div class="Box-sc-g0xbh4-0 hCJWbg text-mono"><div title="18.7 KB" data-testid="blob-size" class="Truncate-sc-1d9305p-0 Jyrkr"><span class="Text-sc-17v1xeu-0 gPDEWA">339 lines (305 loc) · 18.7 KB</span></div></div></div></div><div class="Box-sc-g0xbh4-0 iBylDf"><div class="Box-sc-g0xbh4-0 kSGBPx react-blob-header-edit-and-raw-actions"><div class="ButtonGroup-sc-1gxhls1-0 cjbBGq"><a href="https://github.com/SpotX-CLI/SpotX-Linux/raw/main/install.sh" data-testid="raw-button" data-size="small" data-no-visuals="true" class="types__StyledButton-sc-ws60qy-0 jUWOs"><span data-component="buttonContent" class="Box-sc-g0xbh4-0 kkrdEu"><span data-component="text">Raw</span></span></a><button data-component="IconButton" aria-label="Copy raw content" data-testid="copy-raw-button" data-hotkey="Control+Shift+c" data-size="small" data-no-visuals="true" class="types__StyledButton-sc-ws60qy-0 jJhUyV"><svg aria-hidden="true" focusable="false" role="img" class="octicon octicon-copy" viewBox="0 0 16 16" width="16" height="16" fill="currentColor" style="display: inline-block; user-select: none; vertical-align: text-bottom; overflow: visible;"><path d="M0 6.75C0 5.784.784 5 1.75 5h1.5a.75.75 0 0 1 0 1.5h-1.5a.25.25 0 0 0-.25.25v7.5c0 .138.112.25.25.25h7.5a.25.25 0 0 0 .25-.25v-1.5a.75.75 0 0 1 1.5 0v1.5A1.75 1.75 0 0 1 9.25 16h-7.5A1.75 1.75 0 0 1 0 14.25Z"></path><path d="M5 1.75C5 .784 5.784 0 6.75 0h7.5C15.216 0 16 .784 16 1.75v7.5A1.75 1.75 0 0 1 14.25 11h-7.5A1.75 1.75 0 0 1 5 9.25Zm1.75-.25a.25.25 0 0 0-.25.25v7.5c0 .138.112.25.25.25h7.5a.25.25 0 0 0 .25-.25v-7.5a.25.25 0 0 0-.25-.25Z"></path></svg></button><span role="tooltip" aria-label="Download raw file" class="Tooltip__TooltipBase-sc-uha8qm-0 cogBOk tooltipped-n"><button data-component="IconButton" aria-label="Download raw content" data-testid="download-raw-button" data-size="small" data-no-visuals="true" class="types__StyledButton-sc-ws60qy-0 ftQglq"><svg aria-hidden="true" focusable="false" role="img" class="octicon octicon-download" viewBox="0 0 16 16" width="16" height="16" fill="currentColor" style="display: inline-block; user-select: none; vertical-align: text-bottom; overflow: visible;"><path d="M2.75 14A1.75 1.75 0 0 1 1 12.25v-2.5a.75.75 0 0 1 1.5 0v2.5c0 .138.112.25.25.25h10.5a.25.25 0 0 0 .25-.25v-2.5a.75.75 0 0 1 1.5 0v2.5A1.75 1.75 0 0 1 13.25 14Z"></path><path d="M7.25 7.689V2a.75.75 0 0 1 1.5 0v5.689l1.97-1.969a.749.749 0 1 1 1.06 1.06l-3.25 3.25a.749.749 0 0 1-1.06 0L4.22 6.78a.749.749 0 1 1 1.06-1.06l1.97 1.969Z"></path></svg></button></span></div><button data-testid="raw-button" data-hotkey-scope="read-only-cursor-text-area" hidden=""></button><button data-testid="copy-raw-button" data-hotkey="Control+Shift+c" data-hotkey-scope="read-only-cursor-text-area" hidden=""></button><button data-testid="download-raw-button" data-hotkey-scope="read-only-cursor-text-area" hidden=""></button><a class="Link__StyledLink-sc-14289xe-0 fcmicm js-github-dev-shortcut" data-hotkey="." href="https://github.dev/"></a><button data-testid="" data-hotkey="." data-hotkey-scope="read-only-cursor-text-area" hidden=""></button><div class="ButtonGroup-sc-1gxhls1-0 cjbBGq"><span role="tooltip" aria-label="Fork this repository and edit the file" class="Tooltip__TooltipBase-sc-uha8qm-0 cogBOk tooltipped-nw"><a sx="[object Object]" data-component="IconButton" aria-label="Edit file" data-hotkey="e,E" data-testid="edit-button" data-size="small" data-no-visuals="true" class="types__StyledButton-sc-ws60qy-0 msLiA" href="https://github.com/SpotX-CLI/SpotX-Linux/edit/main/install.sh"><svg aria-hidden="true" focusable="false" role="img" class="octicon octicon-pencil" viewBox="0 0 16 16" width="16" height="16" fill="currentColor" style="display: inline-block; user-select: none; vertical-align: text-bottom; overflow: visible;"><path d="M11.013 1.427a1.75 1.75 0 0 1 2.474 0l1.086 1.086a1.75 1.75 0 0 1 0 2.474l-8.61 8.61c-.21.21-.47.364-.756.445l-3.251.93a.75.75 0 0 1-.927-.928l.929-3.25c.081-.286.235-.547.445-.758l8.61-8.61Zm.176 4.823L9.75 4.81l-6.286 6.287a.253.253 0 0 0-.064.108l-.558 1.953 1.953-.558a.253.253 0 0 0 .108-.064Zm1.238-3.763a.25.25 0 0 0-.354 0L10.811 3.75l1.439 1.44 1.263-1.263a.25.25 0 0 0 0-.354Z"></path></svg></a></span><button data-component="IconButton" aria-label="More edit options" data-testid="more-edit-button" id=":r4:" aria-haspopup="true" tabindex="0" data-size="small" data-no-visuals="true" class="types__StyledButton-sc-ws60qy-0 jJhUyV"><svg aria-hidden="true" focusable="false" role="img" class="octicon octicon-triangle-down" viewBox="0 0 16 16" width="16" height="16" fill="currentColor" style="display: inline-block; user-select: none; vertical-align: text-bottom; overflow: visible;"><path d="m4.427 7.427 3.396 3.396a.25.25 0 0 0 .354 0l3.396-3.396A.25.25 0 0 0 11.396 7H4.604a.25.25 0 0 0-.177.427Z"></path></svg></button></div><button data-testid="" data-hotkey="e,E" data-hotkey-scope="read-only-cursor-text-area" hidden=""></button></div><span role="tooltip" aria-label="Open symbols panel" class="Tooltip__TooltipBase-sc-uha8qm-0 cogBOk tooltipped-nw"><button data-component="IconButton" aria-label="Symbols" aria-pressed="false" aria-expanded="false" aria-controls="symbols-pane" class="types__StyledButton-sc-ws60qy-0 khlyLt" data-testid="symbols-button" id="symbols-button" data-size="small" data-no-visuals="true"><svg aria-hidden="true" focusable="false" role="img" class="octicon octicon-code-square" viewBox="0 0 16 16" width="16" height="16" fill="currentColor" style="display: inline-block; user-select: none; vertical-align: text-bottom; overflow: visible;"><path d="M0 1.75C0 .784.784 0 1.75 0h12.5C15.216 0 16 .784 16 1.75v12.5A1.75 1.75 0 0 1 14.25 16H1.75A1.75 1.75 0 0 1 0 14.25Zm1.75-.25a.25.25 0 0 0-.25.25v12.5c0 .138.112.25.25.25h12.5a.25.25 0 0 0 .25-.25V1.75a.25.25 0 0 0-.25-.25Zm7.47 3.97a.75.75 0 0 1 1.06 0l2 2a.75.75 0 0 1 0 1.06l-2 2a.749.749 0 0 1-1.275-.326.749.749 0 0 1 .215-.734L10.69 8 9.22 6.53a.75.75 0 0 1 0-1.06ZM6.78 6.53 5.31 8l1.47 1.47a.749.749 0 0 1-.326 1.275.749.749 0 0 1-.734-.215l-2-2a.75.75 0 0 1 0-1.06l2-2a.751.751 0 0 1 1.042.018.751.751 0 0 1 .018 1.042Z"></path></svg></button></span><div class="Box-sc-g0xbh4-0 react-blob-header-edit-and-raw-actions-combined"><button data-component="IconButton" aria-label="Edit and raw actions" class="types__StyledButton-sc-ws60qy-0 bxvPoZ js-blob-dropdown-click" title="More file actions" data-testid="more-file-actions-button" id=":r5:" aria-haspopup="true" tabindex="0" data-size="small" data-no-visuals="true"><svg aria-hidden="true" focusable="false" role="img" class="octicon octicon-kebab-horizontal" viewBox="0 0 16 16" width="16" height="16" fill="currentColor" style="display: inline-block; user-select: none; vertical-align: text-bottom; overflow: visible;"><path d="M8 9a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3ZM1.5 9a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3Zm13 0a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3Z"></path></svg></button></div></div></div></div><div class="Box-sc-g0xbh4-0"></div></div></div><div class="Box-sc-g0xbh4-0 kKtuRX"><section aria-labelledby="file-name-id" class="Box-sc-g0xbh4-0 jCjMRf"><div class="Box-sc-g0xbh4-0 TCenl"><div id="highlighted-line-menu-positioner" class="Box-sc-g0xbh4-0 cluMzC"><div class="Box-sc-g0xbh4-0 eRkHwF"><textarea id="read-only-cursor-text-area" aria-label="file content" aria-readonly="true" tabindex="0" aria-multiline="true" aria-haspopup="false" data-gramm="false" data-gramm_editor="false" data-enable-grammarly="false" style="resize: none; margin-top: -2px; padding-left: 80px; width: 100%; background-color: unset; color: var(--color-canvas-default); position: absolute; border: medium none; tab-size: 8; outline: none; overflow: auto hidden; height: 6800px; font-family: ui-monospace, SFMono-Regular, SF Mono, Menlo, Consolas, Liberation Mono, monospace; font-size: 12px; line-height: 20px; overflow-wrap: normal; white-space: pre; caret-color: transparent;" spellcheck="false" autocorrect="off" autocapitalize="none" autocomplete="off" data-ms-editor="false" class="react-blob-print-hide">#!/usr/bin/env
 bash

SPOTX_VERSION="1.2.3.1115-1"

# Dependencies check
command -v perl &gt;/dev/null || { echo -e "\nperl was not found, please
 install. Exiting...\n" &gt;&amp;2; exit 1; }
command -v unzip &gt;/dev/null || { echo -e "\nunzip was not found, 
please install. Exiting...\n" &gt;&amp;2; exit 1; }
command -v zip &gt;/dev/null || { echo -e "\nzip was not found, please 
install. Exiting...\n" &gt;&amp;2; exit 1; }

# Script flags
CACHE_FLAG='false'
EXPERIMENTAL_FLAG='false'
FORCE_FLAG='false'
PATH_FLAG=''
PREMIUM_FLAG='false'

while getopts 'cefhopP:' flag; do
  case "${flag}" in
    c) CACHE_FLAG='true' ;;
    E) EXCLUDE_FLAG+=("${OPTARG}") ;; #currently disabled
    e) EXPERIMENTAL_FLAG='true' ;;
    f) FORCE_FLAG='true' ;;
    h) HIDE_PODCASTS_FLAG='true' ;;
    o) OLD_UI_FLAG='true' ;;
    P) 
      PATH_FLAG="${OPTARG}"
      INSTALL_PATH="${PATH_FLAG}" ;;
    p) PREMIUM_FLAG='true' ;;
    *) 
      echo "Error: Flag not supported."
      exit ;;
  esac
done

# Handle exclude flag(s)
for EXCLUDE_VAL in "${EXCLUDE_FLAG[@]}"; do
  if [[ "${EXCLUDE_VAL}" == "leftsidebar" ]]; then 
EX_LEFTSIDEBAR='true'; fi
done

# Perl command
PERL="perl -pi -w -e"

# Ad-related regex
AD_EMPTY_AD_BLOCK='s|adsEnabled:!0|adsEnabled:!1|'
AD_PLAYLIST_SPONSORS='s|allSponsorships||'
AD_UPGRADE_BUTTON='s/(return|.=.=&gt;)"free"===(.+?)(return|.=.=&gt;)"premium"===/$1"premium"===$2$3"free"===/g'
AD_AUDIO_ADS='s/(case
 .:|async enable\(.\)\{)(this.enabled=.+?\(.{1,3},"audio"\),|return 
this.enabled=...+?\(.{1,3},"audio"\))((;case 
4:)?this.subscription=this.audioApi).+?this.onAdMessage\)/$1$3.cosmosConnector.increaseStreamTime(-100000000000)/'
AD_BILLBOARD='s|.(\?\[.{1,6}[a-zA-Z].leaderboard,)|false$1|'
AD_UPSELL='s|(Enables
 quicksilver in-app messaging modal",default:)(!0)|$1false|'

# Experimental (A/B test) features
ENABLE_ADD_PLAYLIST='s|(Enable support for adding a playlist to another 
playlist",default:)(!1)|$1true|s'
ENABLE_BAD_BUNNY='s|(Enable a different heart button for Bad 
Bunny",default:)(!1)|$1true|s'
ENABLE_BALLOONS='s|(Enable showing balloons on album release date 
anniversaries",default:)(!1)|$1true|s'
ENABLE_BLOCK_USERS='s|(Enable block users feature in 
clientX",default:)(!1)|$1true|s'
ENABLE_CAROUSELS='s|(Use carousels on Home",default:)(!1)|$1true|s'
ENABLE_CLEAR_DOWNLOADS='s|(Enable option in settings to clear all 
downloads",default:)(!1)|$1true|s'
ENABLE_DEVICE_LIST_LOCAL='s|(Enable splitting the device list based on 
local network",default:)(!1)|$1true|s'
ENABLE_DISCOG_SHELF='s|(Enable a condensed disography shelf on artist 
pages",default:)(!1)|$1true|s'
ENABLE_ENHANCE_PLAYLIST='s|(Enable Enhance Playlist UI and functionality
 for end-users",default:)(!1)|$1true|s'
ENABLE_ENHANCE_SONGS='s|(Enable Enhance Liked Songs UI and 
functionality",default:)(!1)|$1true|s'
ENABLE_EQUALIZER='s|(Enable audio equalizer for Desktop and Web 
Player",default:)(!1)|$1true|s'
ENABLE_FOLLOWERS_ON_PROFILE='s|(Enable a setting to control if followers
 and following lists are shown on profile",default:)(!1)|$1true|s'
ENABLE_FORGET_DEVICES='s|(Enable the option to Forget 
Devices",default:)(!1)|$1true|s'
ENABLE_IGNORE_REC='s|(Enable Ignore In Recommendations for desktop and 
web",default:)(!1)|$1true|s'
ENABLE_LIKED_SONGS='s|(Enable Liked Songs section on Artist 
page",default:)(!1)|$1true|s'
ENABLE_LYRICS_CHECK='s|(With this enabled, clients will check whether 
tracks have lyrics available",default:)(!1)|$1true|s'
ENABLE_LYRICS_MATCH='s|(Enable Lyrics match labels in search 
results",default:)(!1)|$1true|s'
ENABLE_PATHFINDER_DATA='s|(Fetch Browse data from 
Pathfinder",default:)(!1)|$1true|s'
ENABLE_PLAYLIST_CREATION_FLOW='s|(Enables new playlist creation flow in 
Web Player and DesktopX",default:)(!1)|$1true|s'
ENABLE_PLAYLIST_PERMISSIONS_FLOWS='s|(Enable Playlist Permissions flows 
for Prod",default:)(!1)|$1true|s'
ENABLE_PODCAST_PLAYBACK_SPEED='s|(playback speed range from 0.5-3.5 with
 every 0.1 increment",default:)(!1)|$1true|s'
ENABLE_PODCAST_TRIMMING='s|(Enable silence trimming in 
podcasts",default:)(!1)|$1true|s'
ENABLE_SEARCH_BOX='s|(Adds a search box so users are able to filter 
playlists when trying to add songs to a playlist using the 
contextmenu",default:)(!1)|$1true|s'
ENABLE_SIMILAR_PLAYLIST='s/,(.\.isOwnedBySelf&amp;&amp;)((\(.{0,11}\)|..createElement)\(.{1,3}Fragment,.+?{(uri:.|spec:.),(uri:.|spec:.).+?contextmenu.create-similar-playlist"\)}\),)/,$2$1/s'

#
 Home screen UI (new)
NEW_UI='s|(Enable the new home structure and 
navigation",values:.,default:)(..DISABLED)|$1true|'
NEW_UI_2='s|(Enable the new home structure and 
navigation",values:.,default:.)(.DISABLED)|$1.ENABLED_CENTER|'
AUDIOBOOKS_CLIENTX='s|(Enable Audiobooks feature on 
ClientX",default:)(!1)|$1true|s'
ENABLE_LEFT_SIDEBAR='s|(Enable Your Library X view of the left 
sidebar",default:)(!1)|$1true|s'
ENABLE_RIGHT_SIDEBAR='s|(Enable the view on the right 
sidebar",default:)(!1)|$1true|s'
ENABLE_RIGHT_SIDEBAR_LYRICS='s|(Show lyrics in the right 
sidebar",default:)(!1)|$1true|s'

# Hide Premium-only features
HIDE_DL_QUALITY='s/(\(.,..jsxs\)\(.{1,3}|(.\(\).|..)createElement\(.{1,4}),\{(filterMatchQuery|filter:.,title|(variant:"viola",semanticColor:"textSubdued"|..:"span",variant:.{3,6}mesto,color:.{3,6}),htmlFor:"desktop.settings.downloadQuality.+?).{1,6}get\("desktop.settings.downloadQuality.title.+?(children:.{1,2}\(.,.\).+?,|\(.,.\){3,4},|,.\)}},.\(.,.\)\),)//'
HIDE_DL_ICON='
 .BKsbV2Xl786X9a09XROH {display:none}'
HIDE_DL_MENU=' button.wC9sIed7pfp47wZbmU6m.pzkhLqffqF_4hucrVVQA 
{display:none}'
HIDE_VERY_HIGH=' 
#desktop\.settings\.streamingQuality&gt;option:nth-child(5) 
{display:none}'

# Hide Podcasts/Episodes/Audiobooks on home screen
HIDE_PODCASTS='s|withQueryParameters\(.\)\{return 
this.queryParameters=.,this}|withQueryParameters(e){return 
this.queryParameters=(e.types?{...e, types: e.types.split(",").filter(_ 
=&gt; !["episode","show"].includes(_)).join(",")}:e),this}|'
HIDE_PODCASTS2='s/(!Array.isArray\(.\)\|\|.===..length)/$1||e.children[0].key.includes('\''episode'\'')||e.children[0].key.includes('\''show'\'')/'
HIDE_PODCASTS3='s/(!Array.isArray\(.\)\|\|.===..length)/$1||e[0].key.includes('\''episode'\'')||e[0].key.includes('\''show'\'')/'

#
 Log-related regex
LOG_1='s|sp://logging/v3/\w+||g'
LOG_SENTRY='s|this\.getStackTop\(\)\.client=e|return;$&amp;|'

# Spotify Connect unlock / UI
CONNECT_OLD_1='s| connect-device-list-item--disabled||' # 1.1.70.610+
CONNECT_OLD_2='s|connect-picker.unavailable-to-control|spotify-connect|'
 # 1.1.70.610+
CONNECT_OLD_3='s|(className:.,disabled:)(..)|$1false|' # 1.1.70.610+
CONNECT_NEW='s/return 
(..isDisabled)(\?(..createElement|\(.{1,10}\))\(..,)/return false$2/' # 
1.1.91.824+
DEVICE_PICKER_NEW='s|(Enable showing a new and improved device picker 
UI",default:)(!1)|$1true|' # 1.1.90.855 - 1.1.95.893
DEVICE_PICKER_OLD='s|(Enable showing a new and improved device picker 
UI",default:)(!0)|$1false|' # 1.1.96.783 - 1.1.97.962

# Credits
echo
echo "**************************"
echo "SpotX-Linux by @SpotX-CLI"
echo "**************************"
echo

# Report SpotX version
echo -e "SpotX-Linux version: ${SPOTX_VERSION}\n"

# Locate install directory
if [ -z ${INSTALL_PATH+x} ]; then
  INSTALL_PATH=$(readlink -e `type -p spotify` 2&gt;/dev/null | rev | 
cut -d/ -f2- | rev)
  if [[ -d "${INSTALL_PATH}" &amp;&amp; "${INSTALL_PATH}" != "/usr/bin" 
]]; then
    echo "Spotify directory found in PATH: ${INSTALL_PATH}"
  elif [[ ! -d "${INSTALL_PATH}" ]]; then
    echo -e "\nSpotify not found in PATH. Searching for Spotify 
directory..."
    INSTALL_PATH=$(timeout 10 find / -type f -path "*/spotify*Apps/*" 
-name "xpui.spa" -size -7M -size +3M -print -quit 2&gt;/dev/null | rev |
 cut -d/ -f3- | rev)
    if [[ -d "${INSTALL_PATH}" ]]; then
      echo "Spotify directory found: ${INSTALL_PATH}"
    elif [[ ! -d "${INSTALL_PATH}" ]]; then
      echo -e "Spotify directory not found. Set directory path with -P 
flag.\nExiting...\n"
      exit; fi
  elif [[ "${INSTALL_PATH}" == "/usr/bin" ]]; then
    echo -e "\nSpotify PATH is set to /usr/bin, searching for Spotify 
directory..."
    INSTALL_PATH=$(timeout 10 find / -type f -path "*/spotify*Apps/*" 
-name "xpui.spa" -size -7M -size +3M -print -quit 2&gt;/dev/null | rev |
 cut -d/ -f3- | rev)
    if [[ -d "${INSTALL_PATH}" &amp;&amp; "${INSTALL_PATH}" != 
"/usr/bin" ]]; then
      echo "Spotify directory found: ${INSTALL_PATH}"
    elif [[ "${INSTALL_PATH}" == "/usr/bin" ]] || [[ ! -d 
"${INSTALL_PATH}" ]]; then
      echo -e "Spotify directory not found. Set directory path with -P 
flag.\nExiting...\n"
      exit; fi; fi
else
  if [[ ! -d "${INSTALL_PATH}" ]]; then
    echo -e "Directory path set by -P was not found.\nExiting...\n"
    exit
  elif [[ ! -f "${INSTALL_PATH}/Apps/xpui.spa" ]]; then
    echo -e "No xpui found in directory provided with -P.\nPlease 
confirm directory and try again or re-install Spotify.\nExiting...\n"
    exit; fi; fi

# Find client version
CLIENT_VERSION=$("${INSTALL_PATH}"/spotify --version | cut -dn -f2- | 
rev | cut -d. -f2- | rev)

# Version function for version comparison
function ver { echo "$@" | awk -F. '{ printf("%d%03d%03d%03d\n", 
$1,$2,$3,$4); }'; }

# Report Spotify version
echo -e "\nSpotify version: ${CLIENT_VERSION}\n"
     
# Path vars
CACHE_PATH="${HOME}/.cache/spotify/"
XPUI_PATH="${INSTALL_PATH}/Apps"
XPUI_DIR="${XPUI_PATH}/xpui"
XPUI_BAK="${XPUI_PATH}/xpui.bak"
XPUI_SPA="${XPUI_PATH}/xpui.spa"
XPUI_JS="${XPUI_DIR}/xpui.js"
XPUI_CSS="${XPUI_DIR}/xpui.css"
HOME_V2_JS="${XPUI_DIR}/home-v2.js"
VENDOR_XPUI_JS="${XPUI_DIR}/vendor~xpui.js"

# xpui detection
if [[ ! -f "${XPUI_SPA}" ]]; then
  echo -e "\nxpui not found!\nReinstall Spotify then try 
again.\nExiting...\n"
  exit
else
  if [[ ! -w "${XPUI_PATH}" ]]; then
    echo -e "\nSpotX does not have write permission in Spotify 
directory.\nRequesting sudo permission...\n"
    sudo chmod a+wr "${INSTALL_PATH}" &amp;&amp; sudo chmod a+wr -R 
"${XPUI_PATH}"; fi
  if [[ "${FORCE_FLAG}" == "false" ]]; then
    if [[ -f "${XPUI_BAK}" ]]; then
      echo "SpotX backup found, SpotX has already been used on this 
install."
      echo -e "Re-run SpotX using the '-f' flag to force xpui 
patching.\n"
      echo "Skipping xpui patches and continuing SpotX..."
      XPUI_SKIP="true"
    else
      echo "Creating xpui backup..."
      cp "${XPUI_SPA}" "${XPUI_BAK}"
      XPUI_SKIP="false"; fi
  else
    if [[ -f "${XPUI_BAK}" ]]; then
      echo "Backup xpui found, restoring original..."
      rm "${XPUI_SPA}"
      cp "${XPUI_BAK}" "${XPUI_SPA}"
      XPUI_SKIP="false"
    else
      echo "Creating xpui backup..."
      cp "${XPUI_SPA}" "${XPUI_BAK}"
      XPUI_SKIP="false"; fi; fi; fi

# Extract xpui.spa
if [[ "${XPUI_SKIP}" == "false" ]]; then
  echo "Extracting xpui..."
  unzip -qq "${XPUI_SPA}" -d "${XPUI_DIR}"
  if grep -Fq "SpotX" "${XPUI_JS}"; then
    echo -e "\nWarning: Detected SpotX patches but no backup file!"
    echo -e "Further xpui patching not allowed until Spotify is 
reinstalled/upgraded.\n"
    echo "Skipping xpui patches and continuing SpotX..."
    XPUI_SKIP="true"
    rm "${XPUI_BAK}" 2&gt;/dev/null
    rm -rf "${XPUI_DIR}" 2&gt;/dev/null
  else
    rm "${XPUI_SPA}"; fi; fi

echo "Applying SpotX patches..."

if [[ "${XPUI_SKIP}" == "false" ]]; then
  if [[ "${PREMIUM_FLAG}" == "false" ]]; then
    # Remove Empty ad block
    echo "Removing ad-related content..."
    $PERL "${AD_EMPTY_AD_BLOCK}" "${XPUI_JS}"
    # Remove Playlist sponsors
    $PERL "${AD_PLAYLIST_SPONSORS}" "${XPUI_JS}"
    # Remove Upgrade button
    $PERL "${AD_UPGRADE_BUTTON}" "${XPUI_JS}"
    # Remove Audio ads
    $PERL "${AD_AUDIO_ADS}" "${XPUI_JS}"
    # Remove billboard ads
    $PERL "${AD_BILLBOARD}" "${XPUI_JS}"
    # Remove premium upsells
    $PERL "${AD_UPSELL}" "${XPUI_JS}"
    
    # Remove Premium-only features
    echo "Removing premium-only features..."
    $PERL "${HIDE_DL_QUALITY}" "${XPUI_JS}"
    echo "${HIDE_DL_ICON}" &gt;&gt; "${XPUI_CSS}"
    echo "${HIDE_DL_MENU}" &gt;&gt; "${XPUI_CSS}"
    echo "${HIDE_VERY_HIGH}" &gt;&gt; "${XPUI_CSS}"
    
    # Unlock Spotify Connect
    echo "Unlocking Spotify Connect..."
    if [[ $(ver "${CLIENT_VERSION}") -ge $(ver "1.1.70.610") &amp;&amp; 
$(ver "${CLIENT_VERSION}") -lt $(ver "1.1.91.824") ]]; then
      $PERL "${CONNECT_OLD_1}" "${XPUI_JS}"
      $PERL "${CONNECT_OLD_2}" "${XPUI_JS}"
      $PERL "${CONNECT_OLD_3}" "${XPUI_JS}"
    elif [[ $(ver "${CLIENT_VERSION}") -ge $(ver "1.1.91.824") 
&amp;&amp; $(ver "${CLIENT_VERSION}") -lt $(ver "1.1.96.783") ]]; then
      $PERL "${DEVICE_PICKER_NEW}" "${XPUI_JS}"
      $PERL "${CONNECT_NEW}" "${XPUI_JS}"
    elif [[ $(ver "${CLIENT_VERSION}") -gt $(ver "1.1.96.783") ]]; then
      $PERL "${CONNECT_NEW}" "${XPUI_JS}"; fi
  else
    echo "Premium subscription setup selected..."; fi; fi

# Experimental patches
if [[ "${XPUI_SKIP}" == "false" ]]; then
  if [[ "${EXPERIMENTAL_FLAG}" == "true" ]]; then
    echo "Adding experimental features..."
    if [[ $(ver "${CLIENT_VERSION}") -ge $(ver "1.1.99.871") ]]; then 
$PERL "${ENABLE_ADD_PLAYLIST}" "${XPUI_JS}"; fi
    if [[ $(ver "${CLIENT_VERSION}") -ge $(ver "1.1.99.871") ]]; then 
$PERL "${ENABLE_BAD_BUNNY}" "${XPUI_JS}"; fi
    if [[ $(ver "${CLIENT_VERSION}") -ge $(ver "1.1.89.854") ]]; then 
$PERL "${ENABLE_BALLOONS}" "${XPUI_JS}"; fi
    if [[ $(ver "${CLIENT_VERSION}") -ge $(ver "1.1.70.610") ]]; then 
$PERL "${ENABLE_BLOCK_USERS}" "${XPUI_JS}"; fi
    if [[ $(ver "${CLIENT_VERSION}") -ge $(ver "1.1.93.896") ]]; then 
$PERL "${ENABLE_CAROUSELS}" "${XPUI_JS}"; fi
    if [[ $(ver "${CLIENT_VERSION}") -ge $(ver "1.1.92.644") &amp;&amp; 
$(ver "${CLIENT_VERSION}") -lt $(ver "1.1.99.871") ]]; then $PERL 
"${ENABLE_CLEAR_DOWNLOADS}" "${XPUI_JS}"; fi
    if [[ $(ver "${CLIENT_VERSION}") -ge $(ver "1.1.99.871") ]]; then 
$PERL "${ENABLE_DEVICE_LIST_LOCAL}" "${XPUI_JS}"; fi
    if [[ $(ver "${CLIENT_VERSION}") -ge $(ver "1.1.79.763") ]]; then 
$PERL "${ENABLE_DISCOG_SHELF}" "${XPUI_JS}"; fi
    if [[ $(ver "${CLIENT_VERSION}") -ge $(ver "1.1.84.716") ]]; then 
$PERL "${ENABLE_ENHANCE_PLAYLIST}" "${XPUI_JS}"; fi
    if [[ $(ver "${CLIENT_VERSION}") -ge $(ver "1.1.86.857") ]]; then 
$PERL "${ENABLE_ENHANCE_SONGS}" "${XPUI_JS}"; fi
    if [[ $(ver "${CLIENT_VERSION}") -ge $(ver "1.1.88.595") ]]; then 
$PERL "${ENABLE_EQUALIZER}" "${XPUI_JS}"; fi
    if [[ $(ver "${CLIENT_VERSION}") -ge $(ver "1.2.1.958") ]]; then 
$PERL "${ENABLE_FOLLOWERS_ON_PROFILE}" "${XPUI_JS}"; fi
    if [[ $(ver "${CLIENT_VERSION}") -ge $(ver "1.2.0.1155") ]]; then 
$PERL "${ENABLE_FORGET_DEVICES}" "${XPUI_JS}"; fi
    if [[ $(ver "${CLIENT_VERSION}") -ge $(ver "1.1.87.612") ]]; then 
$PERL "${ENABLE_IGNORE_REC}" "${XPUI_JS}"; fi
    if [[ $(ver "${CLIENT_VERSION}") -ge $(ver "1.1.70.610") ]]; then 
$PERL "${ENABLE_LIKED_SONGS}" "${XPUI_JS}"; fi
    if [[ $(ver "${CLIENT_VERSION}") -ge $(ver "1.1.70.610") &amp;&amp; 
$(ver "${CLIENT_VERSION}") -lt $(ver "1.1.94.864") ]]; then $PERL 
"${ENABLE_LYRICS_CHECK}" "${XPUI_JS}"; fi
    if [[ $(ver "${CLIENT_VERSION}") -ge $(ver "1.1.87.612") ]]; then 
$PERL "${ENABLE_LYRICS_MATCH}" "${XPUI_JS}"; fi
    if [[ $(ver "${CLIENT_VERSION}") -ge $(ver "1.1.70.610") &amp;&amp; 
$(ver "${CLIENT_VERSION}") -lt $(ver "1.1.96.783") ]]; then $PERL 
"${ENABLE_MADE_FOR_YOU}" "${XPUI_JS}"; fi
    if [[ $(ver "${CLIENT_VERSION}") -ge $(ver "1.1.91.824") ]]; then 
$PERL "${ENABLE_PATHFINDER_DATA}" "${XPUI_JS}"; fi
    if [[ $(ver "${CLIENT_VERSION}") -ge $(ver "1.1.70.610") &amp;&amp; 
$(ver "${CLIENT_VERSION}") -lt $(ver "1.1.94.864") ]]; then $PERL 
"${ENABLE_PLAYLIST_CREATION_FLOW}" "${XPUI_JS}"; fi
    if [[ $(ver "${CLIENT_VERSION}") -ge $(ver "1.1.75.572") ]]; then 
$PERL "${ENABLE_PLAYLIST_PERMISSIONS_FLOWS}" "${XPUI_JS}"; fi
    if [[ $(ver "${CLIENT_VERSION}") -ge $(ver "1.2.0.1165") ]]; then 
$PERL "${ENABLE_PODCAST_PLAYBACK_SPEED}" "${XPUI_JS}"; fi
    if [[ $(ver "${CLIENT_VERSION}") -ge $(ver "1.1.99.871") ]]; then 
$PERL "${ENABLE_PODCAST_TRIMMING}" "${XPUI_JS}"; fi
    if [[ $(ver "${CLIENT_VERSION}") -ge $(ver "1.1.86.857") &amp;&amp; 
$(ver "${CLIENT_VERSION}") -lt $(ver "1.1.94.864") ]]; then $PERL 
"${ENABLE_SEARCH_BOX}" "${XPUI_JS}"; fi
    if [[ $(ver "${CLIENT_VERSION}") -ge $(ver "1.1.85.884") ]]; then 
$PERL "${ENABLE_SIMILAR_PLAYLIST}" "${XPUI_JS}"; fi; fi; fi

# Remove logging
if [[ "${XPUI_SKIP}" == "false" ]]; then
  echo "Removing logging..."
  $PERL "${LOG_1}" "${XPUI_JS}"
  $PERL "${LOG_SENTRY}" "${VENDOR_XPUI_JS}"; fi

# Handle new home screen UI
if [[ "${XPUI_SKIP}" == "false" ]]; then
  if [[ "${OLD_UI_FLAG}" == "true" ]]; then
    echo "Skipping new home UI patch..."
  elif [[ $(ver "${CLIENT_VERSION}") -gt $(ver "1.1.93.896") &amp;&amp; 
$(ver "${CLIENT_VERSION}") -lt $(ver "1.1.97.956") ]]; then
    echo "Enabling new home screen UI..."
    $PERL "${NEW_UI}" "${XPUI_JS}"
    $PERL "${AUDIOBOOKS_CLIENTX}" "${XPUI_JS}"
  elif [[ $(ver "${CLIENT_VERSION}") -ge $(ver "1.1.97.956") &amp;&amp; 
$(ver "${CLIENT_VERSION}") -lt $(ver "1.2.3.1107") ]]; then
    echo "Enabling new home screen UI..."
    $PERL "${NEW_UI_2}" "${XPUI_JS}"
    $PERL "${AUDIOBOOKS_CLIENTX}" "${XPUI_JS}"
    if [[ $(ver "${CLIENT_VERSION}") -ge $(ver "1.1.98.683") ]]; then 
$PERL "${ENABLE_RIGHT_SIDEBAR}" "${XPUI_JS}"; fi
    if [[ $(ver "${CLIENT_VERSION}") -ge $(ver "1.2.0.1165") ]]; then 
$PERL "${ENABLE_RIGHT_SIDEBAR_LYRICS}" "${XPUI_JS}"; fi
  elif [[ $(ver "${CLIENT_VERSION}") -ge $(ver "1.2.3.1107") ]]; then
    echo "Enabling new home screen UI..."
    $PERL "${AUDIOBOOKS_CLIENTX}" "${XPUI_JS}"
    if [[ $(ver "${CLIENT_VERSION}") -ge $(ver "1.1.97.962") ]]; then 
$PERL "${ENABLE_LEFT_SIDEBAR}" "${XPUI_JS}"; fi
    if [[ $(ver "${CLIENT_VERSION}") -ge $(ver "1.1.98.683") ]]; then 
$PERL "${ENABLE_RIGHT_SIDEBAR}" "${XPUI_JS}"; fi
    if [[ $(ver "${CLIENT_VERSION}") -ge $(ver "1.2.0.1165") ]]; then 
$PERL "${ENABLE_RIGHT_SIDEBAR_LYRICS}" "${XPUI_JS}"; fi
  else
    :; fi; fi

# Hide podcasts, episodes and audiobooks on home screen
if [[ "${XPUI_SKIP}" == "false" ]]; then
  if [[ "${HIDE_PODCASTS_FLAG}" == "true" ]]; then
    if [[ $(ver "${CLIENT_VERSION}") -lt $(ver "1.1.93.896") ]]; then
      echo "Hiding non-music items on home screen..."
      $PERL "${HIDE_PODCASTS}" "${XPUI_JS}"
    elif [[ $(ver "${CLIENT_VERSION}") -ge $(ver "1.1.93.896") 
&amp;&amp; $(ver "${CLIENT_VERSION}") -le $(ver "1.1.96.785") ]]; then
      echo "Hiding non-music items on home screen..."
      $PERL "${HIDE_PODCASTS2}" "${HOME_V2_JS}"
    elif [[ $(ver "${CLIENT_VERSION}") -gt $(ver "1.1.96.785") 
&amp;&amp; $(ver "${CLIENT_VERSION}") -lt $(ver "1.1.98.683") ]]; then
      echo "Hiding non-music items on home screen..."
      $PERL "${HIDE_PODCASTS3}" "${HOME_V2_JS}"
    elif [[ $(ver "${CLIENT_VERSION}") -ge $(ver "1.1.98.683") ]]; then
      echo "Hiding non-music items on home screen..."
      $PERL "${HIDE_PODCASTS3}" "${XPUI_JS}"; fi; fi; fi

# Delete app cache
if [[ "${CACHE_FLAG}" == "true" ]]; then
  echo "Clearing app cache..."
  rm -rf "$CACHE_PATH"; fi
  
# Rebuild xpui.spa
if [[ "${XPUI_SKIP}" == "false" ]]; then
  echo "Rebuilding xpui..."
  echo -e "\n//# SpotX was here" &gt;&gt; "${XPUI_JS}"; fi

# Zip files inside xpui folder
if [[ "${XPUI_SKIP}" == "false" ]]; then
  (cd "${XPUI_DIR}"; zip -qq -r ../xpui.spa .)
  rm -rf "${XPUI_DIR}"; fi

echo -e "SpotX finished patching!\n"</textarea><button data-testid="" data-hotkey="Alt+F1" data-hotkey-scope="read-only-cursor-text-area" hidden=""></button><div class="Box-sc-g0xbh4-0 cpgGLU"><div tabindex="0" class="Box-sc-g0xbh4-0 jIrvpW"><div class="Box-sc-g0xbh4-0 bsZDcJ react-code-file-contents" role="presentation" aria-hidden="true" data-tab-size="8" data-paste-markdown-skip="true" style="height: 6780px;" data-hpc="true"><div class="react-line-numbers" style="pointer-events: auto; height: 6780px;"><div data-line-number="1" class="react-line-number react-code-text" style="padding-right: 16px;">1</div><div data-line-number="2" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(20px);">2</div><div data-line-number="3" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(40px);">3</div><div data-line-number="4" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(60px);">4</div><div data-line-number="5" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(80px);">5</div><div data-line-number="6" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(100px);">6</div><div data-line-number="7" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(120px);">7</div><div data-line-number="8" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(140px);">8</div><div data-line-number="9" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(160px);">9</div><div data-line-number="10" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(180px);">10</div><div data-line-number="11" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(200px);">11</div><div data-line-number="12" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(220px);">12</div><div data-line-number="13" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(240px);">13</div><div data-line-number="14" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(260px);">14</div><div data-line-number="15" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(280px);">15</div><div data-line-number="16" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(300px);">16</div><div data-line-number="17" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(320px);">17</div><div data-line-number="18" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(340px);">18</div><div data-line-number="19" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(360px);">19</div><div data-line-number="20" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(380px);">20</div><div data-line-number="21" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(400px);">21</div><div data-line-number="22" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(420px);">22</div><div data-line-number="23" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(440px);">23</div><div data-line-number="24" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(460px);">24</div><div data-line-number="25" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(480px);">25</div><div data-line-number="26" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(500px);">26</div><div data-line-number="27" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(520px);">27</div><div data-line-number="28" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(540px);">28</div><div data-line-number="29" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(560px);">29</div><div data-line-number="30" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(580px);">30</div><div data-line-number="31" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(600px);">31</div><div data-line-number="32" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(620px);">32</div><div data-line-number="33" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(640px);">33</div><div data-line-number="34" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(660px);">34</div><div data-line-number="35" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(680px);">35</div><div data-line-number="36" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(700px);">36</div><div data-line-number="37" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(720px);">37</div><div data-line-number="38" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(740px);">38</div><div data-line-number="39" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(760px);">39</div><div data-line-number="40" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(780px);">40</div><div data-line-number="41" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(800px);">41</div><div data-line-number="42" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(820px);">42</div><div data-line-number="43" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(840px);">43</div><div data-line-number="44" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(860px);">44</div><div data-line-number="45" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(880px);">45</div><div data-line-number="46" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(900px);">46</div><div data-line-number="47" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(920px);">47</div><div data-line-number="48" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(940px);">48</div><div data-line-number="49" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(960px);">49</div><div data-line-number="50" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(980px);">50</div><div data-line-number="51" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(1000px);">51</div><div data-line-number="52" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(1020px);">52</div><div data-line-number="53" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(1040px);">53</div><div data-line-number="54" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(1060px);">54</div><div data-line-number="55" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(1080px);">55</div><div data-line-number="56" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(1100px);">56</div><div data-line-number="57" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(1120px);">57</div><div data-line-number="58" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(1140px);">58</div><div data-line-number="59" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(1160px);">59</div><div data-line-number="60" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(1180px);">60</div><div data-line-number="61" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(1200px);">61</div><div data-line-number="62" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(1220px);">62</div><div data-line-number="63" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(1240px);">63</div><div data-line-number="64" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(1260px);">64</div><div data-line-number="65" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(1280px);">65</div><div data-line-number="66" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(1300px);">66</div><div data-line-number="67" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(1320px);">67</div><div data-line-number="68" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(1340px);">68</div><div data-line-number="69" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(1360px);">69</div><div data-line-number="70" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(1380px);">70</div><div data-line-number="71" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(1400px);">71</div><div data-line-number="72" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(1420px);">72</div><div data-line-number="73" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(1440px);">73</div><div data-line-number="74" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(1460px);">74</div><div data-line-number="75" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(1480px);">75</div><div data-line-number="76" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(1500px);">76</div><div data-line-number="77" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(1520px);">77</div><div data-line-number="78" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(1540px);">78</div><div data-line-number="79" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(1560px);">79</div><div data-line-number="80" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(1580px);">80</div><div data-line-number="81" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(1600px);">81</div><div data-line-number="82" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(1620px);">82</div><div data-line-number="83" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(1640px);">83</div><div data-line-number="84" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(1660px);">84</div><div data-line-number="85" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(1680px);">85</div><div data-line-number="86" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(1700px);">86</div><div data-line-number="87" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(1720px);">87</div><div data-line-number="88" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(1740px);">88</div><div data-line-number="89" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(1760px);">89</div><div data-line-number="90" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(1780px);">90</div><div data-line-number="91" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(1800px);">91</div><div data-line-number="92" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(1820px);">92</div><div data-line-number="93" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(1840px);">93</div><div data-line-number="94" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(1860px);">94</div><div data-line-number="95" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(1880px);">95</div><div data-line-number="96" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(1900px);">96</div><div data-line-number="97" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(1920px);">97</div><div data-line-number="98" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(1940px);">98</div><div data-line-number="99" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(1960px);">99</div><div data-line-number="100" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(1980px);">100</div><div data-line-number="101" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(2000px);">101</div><div data-line-number="102" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(2020px);">102</div><div data-line-number="103" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(2040px);">103</div><div data-line-number="104" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(2060px);">104</div><div data-line-number="105" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(2080px);">105</div><div data-line-number="106" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(2100px);">106</div><div data-line-number="107" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(2120px);">107</div><div data-line-number="108" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(2140px);">108</div><div data-line-number="109" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(2160px);">109</div><div data-line-number="110" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(2180px);">110</div><div data-line-number="111" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(2200px);">111</div><div data-line-number="112" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(2220px);">112</div><div data-line-number="113" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(2240px);">113</div><div data-line-number="114" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(2260px);">114</div><div data-line-number="115" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(2280px);">115</div><div data-line-number="116" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(2300px);">116</div><div data-line-number="117" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(2320px);">117</div><div data-line-number="118" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(2340px);">118</div><div data-line-number="119" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(2360px);">119</div><div data-line-number="120" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(2380px);">120</div><div data-line-number="121" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(2400px);">121</div><div data-line-number="122" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(2420px);">122</div><div data-line-number="123" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(2440px);">123</div><div data-line-number="124" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(2460px);">124</div><div data-line-number="125" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(2480px);">125</div><div data-line-number="126" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(2500px);">126</div><div data-line-number="127" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(2520px);">127</div><div data-line-number="128" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(2540px);">128</div><div data-line-number="129" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(2560px);">129</div><div data-line-number="130" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(2580px);">130</div><div data-line-number="131" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(2600px);">131</div><div data-line-number="132" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(2620px);">132</div><div data-line-number="133" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(2640px);">133</div><div data-line-number="134" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(2660px);">134</div><div data-line-number="135" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(2680px);">135</div><div data-line-number="136" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(2700px);">136</div><div data-line-number="137" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(2720px);">137</div><div data-line-number="138" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(2740px);">138</div><div data-line-number="139" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(2760px);">139</div><div data-line-number="140" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(2780px);">140</div><div data-line-number="141" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(2800px);">141</div><div data-line-number="142" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(2820px);">142</div><div data-line-number="143" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(2840px);">143</div><div data-line-number="144" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(2860px);">144</div><div data-line-number="145" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(2880px);">145</div><div data-line-number="146" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(2900px);">146</div><div data-line-number="147" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(2920px);">147</div><div data-line-number="148" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(2940px);">148</div><div data-line-number="149" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(2960px);">149</div><div data-line-number="150" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(2980px);">150</div><div data-line-number="151" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(3000px);">151</div><div data-line-number="152" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(3020px);">152</div><div data-line-number="153" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(3040px);">153</div><div data-line-number="154" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(3060px);">154</div><div data-line-number="155" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(3080px);">155</div><div data-line-number="156" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(3100px);">156</div><div data-line-number="157" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(3120px);">157</div><div data-line-number="158" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(3140px);">158</div><div data-line-number="159" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(3160px);">159</div><div data-line-number="160" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(3180px);">160</div><div data-line-number="161" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(3200px);">161</div><div data-line-number="162" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(3220px);">162</div><div data-line-number="163" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(3240px);">163</div><div data-line-number="164" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(3260px);">164</div><div data-line-number="165" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(3280px);">165</div><div data-line-number="166" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(3300px);">166</div><div data-line-number="167" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(3320px);">167</div><div data-line-number="168" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(3340px);">168</div><div data-line-number="169" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(3360px);">169</div><div data-line-number="170" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(3380px);">170</div><div data-line-number="171" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(3400px);">171</div><div data-line-number="172" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(3420px);">172</div><div data-line-number="173" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(3440px);">173</div><div data-line-number="174" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(3460px);">174</div><div data-line-number="175" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(3480px);">175</div><div data-line-number="176" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(3500px);">176</div><div data-line-number="177" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(3520px);">177</div><div data-line-number="178" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(3540px);">178</div><div data-line-number="179" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(3560px);">179</div><div data-line-number="180" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(3580px);">180</div><div data-line-number="181" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(3600px);">181</div><div data-line-number="182" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(3620px);">182</div><div data-line-number="183" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(3640px);">183</div><div data-line-number="184" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(3660px);">184</div><div data-line-number="185" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(3680px);">185</div><div data-line-number="186" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(3700px);">186</div><div data-line-number="187" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(3720px);">187</div><div data-line-number="188" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(3740px);">188</div><div data-line-number="189" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(3760px);">189</div><div data-line-number="190" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(3780px);">190</div><div data-line-number="191" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(3800px);">191</div><div data-line-number="192" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(3820px);">192</div><div data-line-number="193" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(3840px);">193</div><div data-line-number="194" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(3860px);">194</div><div data-line-number="195" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(3880px);">195</div><div data-line-number="196" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(3900px);">196</div><div data-line-number="197" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(3920px);">197</div><div data-line-number="198" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(3940px);">198</div><div data-line-number="199" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(3960px);">199</div><div data-line-number="200" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(3980px);">200</div><div data-line-number="201" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(4000px);">201</div><div data-line-number="202" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(4020px);">202</div><div data-line-number="203" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(4040px);">203</div><div data-line-number="204" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(4060px);">204</div><div data-line-number="205" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(4080px);">205</div><div data-line-number="206" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(4100px);">206</div><div data-line-number="207" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(4120px);">207</div><div data-line-number="208" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(4140px);">208</div><div data-line-number="209" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(4160px);">209</div><div data-line-number="210" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(4180px);">210</div><div data-line-number="211" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(4200px);">211</div><div data-line-number="212" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(4220px);">212</div><div data-line-number="213" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(4240px);">213</div><div data-line-number="214" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(4260px);">214</div><div data-line-number="215" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(4280px);">215</div><div data-line-number="216" class="react-line-number react-code-text virtual" style="padding-right: 16px; transform: translateY(4300px);">216</div></div><div class="react-code-lines" style="height: 6780px;"><div data-key="0" class="react-code-text react-code-line-contents" style="min-height: auto;"><div id="LC1" class="react-file-line html-div" data-testid="code-cell" data-line-number="1" style="position: relative;"><span class="pl-c"><span class="pl-c" data-code-text="#!"></span><span data-code-text="/usr/bin/env bash"></span></span></div></div><div data-key="1" class="react-code-text react-code-line-contents virtual" style="transform: translateY(20px); min-height: auto;"><div id="LC2" class="react-file-line html-div" data-testid="code-cell" data-line-number="2" style="position: relative;"><span data-code-text=""></span></div></div><div data-key="2" class="react-code-text react-code-line-contents virtual" style="transform: translateY(40px); min-height: auto;"><div id="LC3" class="react-file-line html-div" data-testid="code-cell" data-line-number="3" style="position: relative;"><span data-code-text="SPOTX_VERSION="></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span data-code-text="1.2.3.1115-1"></span><span class="pl-pds" data-code-text="&quot;"></span></span></div></div><div data-key="3" class="react-code-text react-code-line-contents virtual" style="transform: translateY(60px); min-height: auto;"><div id="LC4" class="react-file-line html-div" data-testid="code-cell" data-line-number="4" style="position: relative;"><span data-code-text=""></span></div></div><div data-key="4" class="react-code-text react-code-line-contents virtual" style="transform: translateY(80px); min-height: auto;"><div id="LC5" class="react-file-line html-div" data-testid="code-cell" data-line-number="5" style="position: relative;"><span class="pl-c"><span class="pl-c" data-code-text="#"></span><span data-code-text=" Dependencies check"></span></span></div></div><div data-key="5" class="react-code-text react-code-line-contents virtual" style="transform: translateY(100px); min-height: auto;"><div id="LC6" class="react-file-line html-div" data-testid="code-cell" data-line-number="6" style="position: relative;"><span class="pl-c1" data-code-text="command"></span><span data-code-text=" -v perl "></span><span class="pl-k" data-code-text="&gt;"></span><span data-code-text="/dev/null "></span><span class="pl-k" data-code-text="||"></span><span data-code-text=" { "></span><span class="pl-c1" data-code-text="echo"></span><span data-code-text=" -e "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span data-code-text="\nperl was not found, please install. Exiting...\n"></span><span class="pl-pds" data-code-text="&quot;"></span></span><span data-code-text=" "></span><span class="pl-k" data-code-text="&gt;&amp;2"></span><span class="pl-k" data-code-text=";"></span><span data-code-text=" "></span><span class="pl-c1" data-code-text="exit"></span><span data-code-text=" 1"></span><span class="pl-k" data-code-text=";"></span><span data-code-text=" }"></span></div></div><div data-key="6" class="react-code-text react-code-line-contents virtual" style="transform: translateY(120px); min-height: auto;"><div id="LC7" class="react-file-line html-div" data-testid="code-cell" data-line-number="7" style="position: relative;"><span class="pl-c1" data-code-text="command"></span><span data-code-text=" -v unzip "></span><span class="pl-k" data-code-text="&gt;"></span><span data-code-text="/dev/null "></span><span class="pl-k" data-code-text="||"></span><span data-code-text=" { "></span><span class="pl-c1" data-code-text="echo"></span><span data-code-text=" -e "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span data-code-text="\nunzip was not found, please install. Exiting...\n"></span><span class="pl-pds" data-code-text="&quot;"></span></span><span data-code-text=" "></span><span class="pl-k" data-code-text="&gt;&amp;2"></span><span class="pl-k" data-code-text=";"></span><span data-code-text=" "></span><span class="pl-c1" data-code-text="exit"></span><span data-code-text=" 1"></span><span class="pl-k" data-code-text=";"></span><span data-code-text=" }"></span></div></div><div data-key="7" class="react-code-text react-code-line-contents virtual" style="transform: translateY(140px); min-height: auto;"><div id="LC8" class="react-file-line html-div" data-testid="code-cell" data-line-number="8" style="position: relative;"><span class="pl-c1" data-code-text="command"></span><span data-code-text=" -v zip "></span><span class="pl-k" data-code-text="&gt;"></span><span data-code-text="/dev/null "></span><span class="pl-k" data-code-text="||"></span><span data-code-text=" { "></span><span class="pl-c1" data-code-text="echo"></span><span data-code-text=" -e "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span data-code-text="\nzip was not found, please install. Exiting...\n"></span><span class="pl-pds" data-code-text="&quot;"></span></span><span data-code-text=" "></span><span class="pl-k" data-code-text="&gt;&amp;2"></span><span class="pl-k" data-code-text=";"></span><span data-code-text=" "></span><span class="pl-c1" data-code-text="exit"></span><span data-code-text=" 1"></span><span class="pl-k" data-code-text=";"></span><span data-code-text=" }"></span></div></div><div data-key="8" class="react-code-text react-code-line-contents virtual" style="transform: translateY(160px); min-height: auto;"><div id="LC9" class="react-file-line html-div" data-testid="code-cell" data-line-number="9" style="position: relative;"><span data-code-text=""></span></div></div><div data-key="9" class="react-code-text react-code-line-contents virtual" style="transform: translateY(180px); min-height: auto;"><div id="LC10" class="react-file-line html-div" data-testid="code-cell" data-line-number="10" style="position: relative;"><span class="pl-c"><span class="pl-c" data-code-text="#"></span><span data-code-text=" Script flags"></span></span></div></div><div data-key="10" class="react-code-text react-code-line-contents virtual" style="transform: translateY(200px); min-height: auto;"><div id="LC11" class="react-file-line html-div" data-testid="code-cell" data-line-number="11" style="position: relative;"><span data-code-text="CACHE_FLAG="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="false"></span><span class="pl-pds" data-code-text="'"></span></span></div></div><div data-key="11" class="react-code-text react-code-line-contents virtual" style="transform: translateY(220px); min-height: auto;"><div id="LC12" class="react-file-line html-div" data-testid="code-cell" data-line-number="12" style="position: relative;"><span data-code-text="EXPERIMENTAL_FLAG="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="false"></span><span class="pl-pds" data-code-text="'"></span></span></div></div><div data-key="12" class="react-code-text react-code-line-contents virtual" style="transform: translateY(240px); min-height: auto;"><div id="LC13" class="react-file-line html-div" data-testid="code-cell" data-line-number="13" style="position: relative;"><span data-code-text="FORCE_FLAG="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="false"></span><span class="pl-pds" data-code-text="'"></span></span></div></div><div data-key="13" class="react-code-text react-code-line-contents virtual" style="transform: translateY(260px); min-height: auto;"><div id="LC14" class="react-file-line html-div" data-testid="code-cell" data-line-number="14" style="position: relative;"><span data-code-text="PATH_FLAG="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span class="pl-pds" data-code-text="'"></span></span></div></div><div data-key="14" class="react-code-text react-code-line-contents virtual" style="transform: translateY(280px); min-height: auto;"><div id="LC15" class="react-file-line html-div" data-testid="code-cell" data-line-number="15" style="position: relative;"><span data-code-text="PREMIUM_FLAG="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="false"></span><span class="pl-pds" data-code-text="'"></span></span></div></div><div data-key="15" class="react-code-text react-code-line-contents virtual" style="transform: translateY(300px); min-height: auto;"><div id="LC16" class="react-file-line html-div" data-testid="code-cell" data-line-number="16" style="position: relative;"><span data-code-text=""></span></div></div><div data-key="16" class="react-code-text react-code-line-contents virtual" style="transform: translateY(320px); min-height: auto;"><div id="LC17" class="react-file-line html-div" data-testid="code-cell" data-line-number="17" style="position: relative;"><span class="pl-k" data-code-text="while"></span><span data-code-text=" "></span><span class="pl-c1" data-code-text="getopts"></span><span data-code-text=" "></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="cefhopP:"></span><span class="pl-pds" data-code-text="'"></span></span><span data-code-text=" flag"></span><span class="pl-k" data-code-text=";"></span><span data-code-text=" "></span><span class="pl-k" data-code-text="do"></span></div></div><div data-key="17" class="react-code-text react-code-line-contents virtual" style="transform: translateY(340px); min-height: auto;"><div id="LC18" class="react-file-line html-div" data-testid="code-cell" data-line-number="18" style="position: relative;"><span data-code-text="  "></span><span class="pl-k" data-code-text="case"></span><span data-code-text=" "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span class="pl-smi" data-code-text="${flag}"></span><span class="pl-pds" data-code-text="&quot;"></span></span><span data-code-text=" "></span><span class="pl-k" data-code-text="in"></span></div></div><div data-key="18" class="react-code-text react-code-line-contents virtual" style="transform: translateY(360px); min-height: auto;"><div id="LC19" class="react-file-line html-div" data-testid="code-cell" data-line-number="19" style="position: relative;"><span data-code-text="    c) CACHE_FLAG="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="true"></span><span class="pl-pds" data-code-text="'"></span></span><span data-code-text=" ;;"></span></div></div><div data-key="19" class="react-code-text react-code-line-contents virtual" style="transform: translateY(380px); min-height: auto;"><div id="LC20" class="react-file-line html-div" data-testid="code-cell" data-line-number="20" style="position: relative;"><span data-code-text="    E) EXCLUDE_FLAG+=("></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span class="pl-smi" data-code-text="${OPTARG}"></span><span class="pl-pds" data-code-text="&quot;"></span></span><span data-code-text=") ;; "></span><span class="pl-c"><span class="pl-c" data-code-text="#"></span><span data-code-text="currently disabled"></span></span></div></div><div data-key="20" class="react-code-text react-code-line-contents virtual" style="transform: translateY(400px); min-height: auto;"><div id="LC21" class="react-file-line html-div" data-testid="code-cell" data-line-number="21" style="position: relative;"><span data-code-text="    e) EXPERIMENTAL_FLAG="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="true"></span><span class="pl-pds" data-code-text="'"></span></span><span data-code-text=" ;;"></span></div></div><div data-key="21" class="react-code-text react-code-line-contents virtual" style="transform: translateY(420px); min-height: auto;"><div id="LC22" class="react-file-line html-div" data-testid="code-cell" data-line-number="22" style="position: relative;"><span data-code-text="    f) FORCE_FLAG="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="true"></span><span class="pl-pds" data-code-text="'"></span></span><span data-code-text=" ;;"></span></div></div><div data-key="22" class="react-code-text react-code-line-contents virtual" style="transform: translateY(440px); min-height: auto;"><div id="LC23" class="react-file-line html-div" data-testid="code-cell" data-line-number="23" style="position: relative;"><span data-code-text="    h) HIDE_PODCASTS_FLAG="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="true"></span><span class="pl-pds" data-code-text="'"></span></span><span data-code-text=" ;;"></span></div></div><div data-key="23" class="react-code-text react-code-line-contents virtual" style="transform: translateY(460px); min-height: auto;"><div id="LC24" class="react-file-line html-div" data-testid="code-cell" data-line-number="24" style="position: relative;"><span data-code-text="    o) OLD_UI_FLAG="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="true"></span><span class="pl-pds" data-code-text="'"></span></span><span data-code-text=" ;;"></span></div></div><div data-key="24" class="react-code-text react-code-line-contents virtual" style="transform: translateY(480px); min-height: auto;"><div id="LC25" class="react-file-line html-div" data-testid="code-cell" data-line-number="25" style="position: relative;"><span data-code-text="    P) "></span></div></div><div data-key="25" class="react-code-text react-code-line-contents virtual" style="transform: translateY(500px); min-height: auto;"><div id="LC26" class="react-file-line html-div" data-testid="code-cell" data-line-number="26" style="position: relative;"><span data-code-text="      PATH_FLAG="></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span class="pl-smi" data-code-text="${OPTARG}"></span><span class="pl-pds" data-code-text="&quot;"></span></span></div></div><div data-key="26" class="react-code-text react-code-line-contents virtual" style="transform: translateY(520px); min-height: auto;"><div id="LC27" class="react-file-line html-div" data-testid="code-cell" data-line-number="27" style="position: relative;"><span data-code-text="      INSTALL_PATH="></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span class="pl-smi" data-code-text="${PATH_FLAG}"></span><span class="pl-pds" data-code-text="&quot;"></span></span><span data-code-text=" ;;"></span></div></div><div data-key="27" class="react-code-text react-code-line-contents virtual" style="transform: translateY(540px); min-height: auto;"><div id="LC28" class="react-file-line html-div" data-testid="code-cell" data-line-number="28" style="position: relative;"><span data-code-text="    p) PREMIUM_FLAG="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="true"></span><span class="pl-pds" data-code-text="'"></span></span><span data-code-text=" ;;"></span></div></div><div data-key="28" class="react-code-text react-code-line-contents virtual" style="transform: translateY(560px); min-height: auto;"><div id="LC29" class="react-file-line html-div" data-testid="code-cell" data-line-number="29" style="position: relative;"><span data-code-text="    "></span><span class="pl-k" data-code-text="*"></span><span data-code-text=") "></span></div></div><div data-key="29" class="react-code-text react-code-line-contents virtual" style="transform: translateY(580px); min-height: auto;"><div id="LC30" class="react-file-line html-div" data-testid="code-cell" data-line-number="30" style="position: relative;"><span data-code-text="      "></span><span class="pl-c1" data-code-text="echo"></span><span data-code-text=" "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span data-code-text="Error: Flag not supported."></span><span class="pl-pds" data-code-text="&quot;"></span></span></div></div><div data-key="30" class="react-code-text react-code-line-contents virtual" style="transform: translateY(600px); min-height: auto;"><div id="LC31" class="react-file-line html-div" data-testid="code-cell" data-line-number="31" style="position: relative;"><span data-code-text="      "></span><span class="pl-c1" data-code-text="exit"></span><span data-code-text=" ;;"></span></div></div><div data-key="31" class="react-code-text react-code-line-contents virtual" style="transform: translateY(620px); min-height: auto;"><div id="LC32" class="react-file-line html-div" data-testid="code-cell" data-line-number="32" style="position: relative;"><span data-code-text="  "></span><span class="pl-k" data-code-text="esac"></span></div></div><div data-key="32" class="react-code-text react-code-line-contents virtual" style="transform: translateY(640px); min-height: auto;"><div id="LC33" class="react-file-line html-div" data-testid="code-cell" data-line-number="33" style="position: relative;"><span class="pl-k" data-code-text="done"></span></div></div><div data-key="33" class="react-code-text react-code-line-contents virtual" style="transform: translateY(660px); min-height: auto;"><div id="LC34" class="react-file-line html-div" data-testid="code-cell" data-line-number="34" style="position: relative;"><span data-code-text=""></span></div></div><div data-key="34" class="react-code-text react-code-line-contents virtual" style="transform: translateY(680px); min-height: auto;"><div id="LC35" class="react-file-line html-div" data-testid="code-cell" data-line-number="35" style="position: relative;"><span class="pl-c"><span class="pl-c" data-code-text="#"></span><span data-code-text=" Handle exclude flag(s)"></span></span></div></div><div data-key="35" class="react-code-text react-code-line-contents virtual" style="transform: translateY(700px); min-height: auto;"><div id="LC36" class="react-file-line html-div" data-testid="code-cell" data-line-number="36" style="position: relative;"><span class="pl-k" data-code-text="for"></span><span data-code-text=" "></span><span class="pl-smi" data-code-text="EXCLUDE_VAL"></span><span data-code-text=" "></span><span class="pl-k" data-code-text="in"></span><span data-code-text=" "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span class="pl-smi" data-code-text="${EXCLUDE_FLAG[@]}"></span><span class="pl-pds" data-code-text="&quot;"></span></span><span class="pl-k" data-code-text=";"></span><span data-code-text=" "></span><span class="pl-k" data-code-text="do"></span></div></div><div data-key="36" class="react-code-text react-code-line-contents virtual" style="transform: translateY(720px); min-height: auto;"><div id="LC37" class="react-file-line html-div" data-testid="code-cell" data-line-number="37" style="position: relative;"><span data-code-text="  "></span><span class="pl-k" data-code-text="if"></span><span data-code-text=" [[ "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span class="pl-smi" data-code-text="${EXCLUDE_VAL}"></span><span class="pl-pds" data-code-text="&quot;"></span></span><span data-code-text=" "></span><span class="pl-k" data-code-text="=="></span><span data-code-text=" "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span data-code-text="leftsidebar"></span><span class="pl-pds" data-code-text="&quot;"></span></span><span data-code-text=" ]]"></span><span class="pl-k" data-code-text=";"></span><span data-code-text=" "></span><span class="pl-k" data-code-text="then"></span><span data-code-text=" EX_LEFTSIDEBAR="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="true"></span><span class="pl-pds" data-code-text="'"></span></span><span class="pl-k" data-code-text=";"></span><span data-code-text=" "></span><span class="pl-k" data-code-text="fi"></span></div></div><div data-key="37" class="react-code-text react-code-line-contents virtual" style="transform: translateY(740px); min-height: auto;"><div id="LC38" class="react-file-line html-div" data-testid="code-cell" data-line-number="38" style="position: relative;"><span class="pl-k" data-code-text="done"></span></div></div><div data-key="38" class="react-code-text react-code-line-contents virtual" style="transform: translateY(760px); min-height: auto;"><div id="LC39" class="react-file-line html-div" data-testid="code-cell" data-line-number="39" style="position: relative;"><span data-code-text=""></span></div></div><div data-key="39" class="react-code-text react-code-line-contents virtual" style="transform: translateY(780px); min-height: auto;"><div id="LC40" class="react-file-line html-div" data-testid="code-cell" data-line-number="40" style="position: relative;"><span class="pl-c"><span class="pl-c" data-code-text="#"></span><span data-code-text=" Perl command"></span></span></div></div><div data-key="40" class="react-code-text react-code-line-contents virtual" style="transform: translateY(800px); min-height: auto;"><div id="LC41" class="react-file-line html-div" data-testid="code-cell" data-line-number="41" style="position: relative;"><span data-code-text="PERL="></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span data-code-text="perl -pi -w -e"></span><span class="pl-pds" data-code-text="&quot;"></span></span></div></div><div data-key="41" class="react-code-text react-code-line-contents virtual" style="transform: translateY(820px); min-height: auto;"><div id="LC42" class="react-file-line html-div" data-testid="code-cell" data-line-number="42" style="position: relative;"><span data-code-text=""></span></div></div><div data-key="42" class="react-code-text react-code-line-contents virtual" style="transform: translateY(840px); min-height: auto;"><div id="LC43" class="react-file-line html-div" data-testid="code-cell" data-line-number="43" style="position: relative;"><span class="pl-c"><span class="pl-c" data-code-text="#"></span><span data-code-text=" Ad-related regex"></span></span></div></div><div data-key="43" class="react-code-text react-code-line-contents virtual" style="transform: translateY(860px); min-height: auto;"><div id="LC44" class="react-file-line html-div" data-testid="code-cell" data-line-number="44" style="position: relative;"><span data-code-text="AD_EMPTY_AD_BLOCK="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="s|adsEnabled:!0|adsEnabled:!1|"></span><span class="pl-pds" data-code-text="'"></span></span></div></div><div data-key="44" class="react-code-text react-code-line-contents virtual" style="transform: translateY(880px); min-height: auto;"><div id="LC45" class="react-file-line html-div" data-testid="code-cell" data-line-number="45" style="position: relative;"><span data-code-text="AD_PLAYLIST_SPONSORS="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="s|allSponsorships||"></span><span class="pl-pds" data-code-text="'"></span></span></div></div><div data-key="45" class="react-code-text react-code-line-contents virtual" style="transform: translateY(900px); min-height: auto;"><div id="LC46" class="react-file-line html-div" data-testid="code-cell" data-line-number="46" style="position: relative;"><span data-code-text="AD_UPGRADE_BUTTON="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="s/(return|.=.=&gt;)&quot;free&quot;===(.+?)(return|.=.=&gt;)&quot;premium&quot;===/$1&quot;premium&quot;===$2$3&quot;free&quot;===/g"></span><span class="pl-pds" data-code-text="'"></span></span></div></div><div data-key="46" class="react-code-text react-code-line-contents virtual" style="transform: translateY(920px); min-height: auto;"><div id="LC47" class="react-file-line html-div" data-testid="code-cell" data-line-number="47" style="position: relative;"><span data-code-text="AD_AUDIO_ADS="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="s/(case .:|async enable\(.\)\{)(this.enabled=.+?\(.{1,3},&quot;audio&quot;\),|return this.enabled=...+?\(.{1,3},&quot;audio&quot;\))((;case 4:)?this.subscription=this.audioApi).+?this.onAdMessage\)/$1$3.cosmosConnector.increaseStreamTime(-100000000000)/"></span><span class="pl-pds" data-code-text="'"></span></span></div></div><div data-key="47" class="react-code-text react-code-line-contents virtual" style="transform: translateY(940px); min-height: auto;"><div id="LC48" class="react-file-line html-div" data-testid="code-cell" data-line-number="48" style="position: relative;"><span data-code-text="AD_BILLBOARD="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="s|.(\?\[.{1,6}[a-zA-Z].leaderboard,)|false$1|"></span><span class="pl-pds" data-code-text="'"></span></span></div></div><div data-key="48" class="react-code-text react-code-line-contents virtual" style="transform: translateY(960px); min-height: auto;"><div id="LC49" class="react-file-line html-div" data-testid="code-cell" data-line-number="49" style="position: relative;"><span data-code-text="AD_UPSELL="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="s|(Enables quicksilver in-app messaging modal&quot;,default:)(!0)|$1false|"></span><span class="pl-pds" data-code-text="'"></span></span></div></div><div data-key="49" class="react-code-text react-code-line-contents virtual" style="transform: translateY(980px); min-height: auto;"><div id="LC50" class="react-file-line html-div" data-testid="code-cell" data-line-number="50" style="position: relative;"><span data-code-text=""></span></div></div><div data-key="50" class="react-code-text react-code-line-contents virtual" style="transform: translateY(1000px); min-height: auto;"><div id="LC51" class="react-file-line html-div" data-testid="code-cell" data-line-number="51" style="position: relative;"><span class="pl-c"><span class="pl-c" data-code-text="#"></span><span data-code-text=" Experimental (A/B test) features"></span></span></div></div><div data-key="51" class="react-code-text react-code-line-contents virtual" style="transform: translateY(1020px); min-height: auto;"><div id="LC52" class="react-file-line html-div" data-testid="code-cell" data-line-number="52" style="position: relative;"><span data-code-text="ENABLE_ADD_PLAYLIST="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="s|(Enable support for adding a playlist to another playlist&quot;,default:)(!1)|$1true|s"></span><span class="pl-pds" data-code-text="'"></span></span></div></div><div data-key="52" class="react-code-text react-code-line-contents virtual" style="transform: translateY(1040px); min-height: auto;"><div id="LC53" class="react-file-line html-div" data-testid="code-cell" data-line-number="53" style="position: relative;"><span data-code-text="ENABLE_BAD_BUNNY="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="s|(Enable a different heart button for Bad Bunny&quot;,default:)(!1)|$1true|s"></span><span class="pl-pds" data-code-text="'"></span></span></div></div><div data-key="53" class="react-code-text react-code-line-contents virtual" style="transform: translateY(1060px); min-height: auto;"><div id="LC54" class="react-file-line html-div" data-testid="code-cell" data-line-number="54" style="position: relative;"><span data-code-text="ENABLE_BALLOONS="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="s|(Enable showing balloons on album release date anniversaries&quot;,default:)(!1)|$1true|s"></span><span class="pl-pds" data-code-text="'"></span></span></div></div><div data-key="54" class="react-code-text react-code-line-contents virtual" style="transform: translateY(1080px); min-height: auto;"><div id="LC55" class="react-file-line html-div" data-testid="code-cell" data-line-number="55" style="position: relative;"><span data-code-text="ENABLE_BLOCK_USERS="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="s|(Enable block users feature in clientX&quot;,default:)(!1)|$1true|s"></span><span class="pl-pds" data-code-text="'"></span></span></div></div><div data-key="55" class="react-code-text react-code-line-contents virtual" style="transform: translateY(1100px); min-height: auto;"><div id="LC56" class="react-file-line html-div" data-testid="code-cell" data-line-number="56" style="position: relative;"><span data-code-text="ENABLE_CAROUSELS="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="s|(Use carousels on Home&quot;,default:)(!1)|$1true|s"></span><span class="pl-pds" data-code-text="'"></span></span></div></div><div data-key="56" class="react-code-text react-code-line-contents virtual" style="transform: translateY(1120px); min-height: auto;"><div id="LC57" class="react-file-line html-div" data-testid="code-cell" data-line-number="57" style="position: relative;"><span data-code-text="ENABLE_CLEAR_DOWNLOADS="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="s|(Enable option in settings to clear all downloads&quot;,default:)(!1)|$1true|s"></span><span class="pl-pds" data-code-text="'"></span></span></div></div><div data-key="57" class="react-code-text react-code-line-contents virtual" style="transform: translateY(1140px); min-height: auto;"><div id="LC58" class="react-file-line html-div" data-testid="code-cell" data-line-number="58" style="position: relative;"><span data-code-text="ENABLE_DEVICE_LIST_LOCAL="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="s|(Enable splitting the device list based on local network&quot;,default:)(!1)|$1true|s"></span><span class="pl-pds" data-code-text="'"></span></span></div></div><div data-key="58" class="react-code-text react-code-line-contents virtual" style="transform: translateY(1160px); min-height: auto;"><div id="LC59" class="react-file-line html-div" data-testid="code-cell" data-line-number="59" style="position: relative;"><span data-code-text="ENABLE_DISCOG_SHELF="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="s|(Enable a condensed disography shelf on artist pages&quot;,default:)(!1)|$1true|s"></span><span class="pl-pds" data-code-text="'"></span></span></div></div><div data-key="59" class="react-code-text react-code-line-contents virtual" style="transform: translateY(1180px); min-height: auto;"><div id="LC60" class="react-file-line html-div" data-testid="code-cell" data-line-number="60" style="position: relative;"><span data-code-text="ENABLE_ENHANCE_PLAYLIST="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="s|(Enable Enhance Playlist UI and functionality for end-users&quot;,default:)(!1)|$1true|s"></span><span class="pl-pds" data-code-text="'"></span></span></div></div><div data-key="60" class="react-code-text react-code-line-contents virtual" style="transform: translateY(1200px); min-height: auto;"><div id="LC61" class="react-file-line html-div" data-testid="code-cell" data-line-number="61" style="position: relative;"><span data-code-text="ENABLE_ENHANCE_SONGS="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="s|(Enable Enhance Liked Songs UI and functionality&quot;,default:)(!1)|$1true|s"></span><span class="pl-pds" data-code-text="'"></span></span></div></div><div data-key="61" class="react-code-text react-code-line-contents virtual" style="transform: translateY(1220px); min-height: auto;"><div id="LC62" class="react-file-line html-div" data-testid="code-cell" data-line-number="62" style="position: relative;"><span data-code-text="ENABLE_EQUALIZER="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="s|(Enable audio equalizer for Desktop and Web Player&quot;,default:)(!1)|$1true|s"></span><span class="pl-pds" data-code-text="'"></span></span></div></div><div data-key="62" class="react-code-text react-code-line-contents virtual" style="transform: translateY(1240px); min-height: auto;"><div id="LC63" class="react-file-line html-div" data-testid="code-cell" data-line-number="63" style="position: relative;"><span data-code-text="ENABLE_FOLLOWERS_ON_PROFILE="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="s|(Enable a setting to control if followers and following lists are shown on profile&quot;,default:)(!1)|$1true|s"></span><span class="pl-pds" data-code-text="'"></span></span></div></div><div data-key="63" class="react-code-text react-code-line-contents virtual" style="transform: translateY(1260px); min-height: auto;"><div id="LC64" class="react-file-line html-div" data-testid="code-cell" data-line-number="64" style="position: relative;"><span data-code-text="ENABLE_FORGET_DEVICES="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="s|(Enable the option to Forget Devices&quot;,default:)(!1)|$1true|s"></span><span class="pl-pds" data-code-text="'"></span></span></div></div><div data-key="64" class="react-code-text react-code-line-contents virtual" style="transform: translateY(1280px); min-height: auto;"><div id="LC65" class="react-file-line html-div" data-testid="code-cell" data-line-number="65" style="position: relative;"><span data-code-text="ENABLE_IGNORE_REC="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="s|(Enable Ignore In Recommendations for desktop and web&quot;,default:)(!1)|$1true|s"></span><span class="pl-pds" data-code-text="'"></span></span></div></div><div data-key="65" class="react-code-text react-code-line-contents virtual" style="transform: translateY(1300px); min-height: auto;"><div id="LC66" class="react-file-line html-div" data-testid="code-cell" data-line-number="66" style="position: relative;"><span data-code-text="ENABLE_LIKED_SONGS="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="s|(Enable Liked Songs section on Artist page&quot;,default:)(!1)|$1true|s"></span><span class="pl-pds" data-code-text="'"></span></span></div></div><div data-key="66" class="react-code-text react-code-line-contents virtual" style="transform: translateY(1320px); min-height: auto;"><div id="LC67" class="react-file-line html-div" data-testid="code-cell" data-line-number="67" style="position: relative;"><span data-code-text="ENABLE_LYRICS_CHECK="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="s|(With this enabled, clients will check whether tracks have lyrics available&quot;,default:)(!1)|$1true|s"></span><span class="pl-pds" data-code-text="'"></span></span></div></div><div data-key="67" class="react-code-text react-code-line-contents virtual" style="transform: translateY(1340px); min-height: auto;"><div id="LC68" class="react-file-line html-div" data-testid="code-cell" data-line-number="68" style="position: relative;"><span data-code-text="ENABLE_LYRICS_MATCH="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="s|(Enable Lyrics match labels in search results&quot;,default:)(!1)|$1true|s"></span><span class="pl-pds" data-code-text="'"></span></span></div></div><div data-key="68" class="react-code-text react-code-line-contents virtual" style="transform: translateY(1360px); min-height: auto;"><div id="LC69" class="react-file-line html-div" data-testid="code-cell" data-line-number="69" style="position: relative;"><span data-code-text="ENABLE_PATHFINDER_DATA="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="s|(Fetch Browse data from Pathfinder&quot;,default:)(!1)|$1true|s"></span><span class="pl-pds" data-code-text="'"></span></span></div></div><div data-key="69" class="react-code-text react-code-line-contents virtual" style="transform: translateY(1380px); min-height: auto;"><div id="LC70" class="react-file-line html-div" data-testid="code-cell" data-line-number="70" style="position: relative;"><span data-code-text="ENABLE_PLAYLIST_CREATION_FLOW="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="s|(Enables new playlist creation flow in Web Player and DesktopX&quot;,default:)(!1)|$1true|s"></span><span class="pl-pds" data-code-text="'"></span></span></div></div><div data-key="70" class="react-code-text react-code-line-contents virtual" style="transform: translateY(1400px); min-height: auto;"><div id="LC71" class="react-file-line html-div" data-testid="code-cell" data-line-number="71" style="position: relative;"><span data-code-text="ENABLE_PLAYLIST_PERMISSIONS_FLOWS="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="s|(Enable Playlist Permissions flows for Prod&quot;,default:)(!1)|$1true|s"></span><span class="pl-pds" data-code-text="'"></span></span></div></div><div data-key="71" class="react-code-text react-code-line-contents virtual" style="transform: translateY(1420px); min-height: auto;"><div id="LC72" class="react-file-line html-div" data-testid="code-cell" data-line-number="72" style="position: relative;"><span data-code-text="ENABLE_PODCAST_PLAYBACK_SPEED="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="s|(playback speed range from 0.5-3.5 with every 0.1 increment&quot;,default:)(!1)|$1true|s"></span><span class="pl-pds" data-code-text="'"></span></span></div></div><div data-key="72" class="react-code-text react-code-line-contents virtual" style="transform: translateY(1440px); min-height: auto;"><div id="LC73" class="react-file-line html-div" data-testid="code-cell" data-line-number="73" style="position: relative;"><span data-code-text="ENABLE_PODCAST_TRIMMING="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="s|(Enable silence trimming in podcasts&quot;,default:)(!1)|$1true|s"></span><span class="pl-pds" data-code-text="'"></span></span></div></div><div data-key="73" class="react-code-text react-code-line-contents virtual" style="transform: translateY(1460px); min-height: auto;"><div id="LC74" class="react-file-line html-div" data-testid="code-cell" data-line-number="74" style="position: relative;"><span data-code-text="ENABLE_SEARCH_BOX="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="s|(Adds a search box so users are able to filter playlists when trying to add songs to a playlist using the contextmenu&quot;,default:)(!1)|$1true|s"></span><span class="pl-pds" data-code-text="'"></span></span></div></div><div data-key="74" class="react-code-text react-code-line-contents virtual" style="transform: translateY(1480px); min-height: auto;"><div id="LC75" class="react-file-line html-div" data-testid="code-cell" data-line-number="75" style="position: relative;"><span data-code-text="ENABLE_SIMILAR_PLAYLIST="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="s/,(.\.isOwnedBySelf&amp;&amp;)((\(.{0,11}\)|..createElement)\(.{1,3}Fragment,.+?{(uri:.|spec:.),(uri:.|spec:.).+?contextmenu.create-similar-playlist&quot;\)}\),)/,$2$1/s"></span><span class="pl-pds" data-code-text="'"></span></span></div></div><div data-key="75" class="react-code-text react-code-line-contents virtual" style="transform: translateY(1500px); min-height: auto;"><div id="LC76" class="react-file-line html-div" data-testid="code-cell" data-line-number="76" style="position: relative;"><span data-code-text=""></span></div></div><div data-key="76" class="react-code-text react-code-line-contents virtual" style="transform: translateY(1520px); min-height: auto;"><div id="LC77" class="react-file-line html-div" data-testid="code-cell" data-line-number="77" style="position: relative;"><span class="pl-c"><span class="pl-c" data-code-text="#"></span><span data-code-text=" Home screen UI (new)"></span></span></div></div><div data-key="77" class="react-code-text react-code-line-contents virtual" style="transform: translateY(1540px); min-height: auto;"><div id="LC78" class="react-file-line html-div" data-testid="code-cell" data-line-number="78" style="position: relative;"><span data-code-text="NEW_UI="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="s|(Enable the new home structure and navigation&quot;,values:.,default:)(..DISABLED)|$1true|"></span><span class="pl-pds" data-code-text="'"></span></span></div></div><div data-key="78" class="react-code-text react-code-line-contents virtual" style="transform: translateY(1560px); min-height: auto;"><div id="LC79" class="react-file-line html-div" data-testid="code-cell" data-line-number="79" style="position: relative;"><span data-code-text="NEW_UI_2="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="s|(Enable the new home structure and navigation&quot;,values:.,default:.)(.DISABLED)|$1.ENABLED_CENTER|"></span><span class="pl-pds" data-code-text="'"></span></span></div></div><div data-key="79" class="react-code-text react-code-line-contents virtual" style="transform: translateY(1580px); min-height: auto;"><div id="LC80" class="react-file-line html-div" data-testid="code-cell" data-line-number="80" style="position: relative;"><span data-code-text="AUDIOBOOKS_CLIENTX="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="s|(Enable Audiobooks feature on ClientX&quot;,default:)(!1)|$1true|s"></span><span class="pl-pds" data-code-text="'"></span></span></div></div><div data-key="80" class="react-code-text react-code-line-contents virtual" style="transform: translateY(1600px); min-height: auto;"><div id="LC81" class="react-file-line html-div" data-testid="code-cell" data-line-number="81" style="position: relative;"><span data-code-text="ENABLE_LEFT_SIDEBAR="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="s|(Enable Your Library X view of the left sidebar&quot;,default:)(!1)|$1true|s"></span><span class="pl-pds" data-code-text="'"></span></span></div></div><div data-key="81" class="react-code-text react-code-line-contents virtual" style="transform: translateY(1620px); min-height: auto;"><div id="LC82" class="react-file-line html-div" data-testid="code-cell" data-line-number="82" style="position: relative;"><span data-code-text="ENABLE_RIGHT_SIDEBAR="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="s|(Enable the view on the right sidebar&quot;,default:)(!1)|$1true|s"></span><span class="pl-pds" data-code-text="'"></span></span></div></div><div data-key="82" class="react-code-text react-code-line-contents virtual" style="transform: translateY(1640px); min-height: auto;"><div id="LC83" class="react-file-line html-div" data-testid="code-cell" data-line-number="83" style="position: relative;"><span data-code-text="ENABLE_RIGHT_SIDEBAR_LYRICS="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="s|(Show lyrics in the right sidebar&quot;,default:)(!1)|$1true|s"></span><span class="pl-pds" data-code-text="'"></span></span></div></div><div data-key="83" class="react-code-text react-code-line-contents virtual" style="transform: translateY(1660px); min-height: auto;"><div id="LC84" class="react-file-line html-div" data-testid="code-cell" data-line-number="84" style="position: relative;"><span data-code-text=""></span></div></div><div data-key="84" class="react-code-text react-code-line-contents virtual" style="transform: translateY(1680px); min-height: auto;"><div id="LC85" class="react-file-line html-div" data-testid="code-cell" data-line-number="85" style="position: relative;"><span class="pl-c"><span class="pl-c" data-code-text="#"></span><span data-code-text=" Hide Premium-only features"></span></span></div></div><div data-key="85" class="react-code-text react-code-line-contents virtual" style="transform: translateY(1700px); min-height: auto;"><div id="LC86" class="react-file-line html-div" data-testid="code-cell" data-line-number="86" style="position: relative;"><span data-code-text="HIDE_DL_QUALITY="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="s/(\(.,..jsxs\)\(.{1,3}|(.\(\).|..)createElement\(.{1,4}),\{(filterMatchQuery|filter:.,title|(variant:&quot;viola&quot;,semanticColor:&quot;textSubdued&quot;|..:&quot;span&quot;,variant:.{3,6}mesto,color:.{3,6}),htmlFor:&quot;desktop.settings.downloadQuality.+?).{1,6}get\(&quot;desktop.settings.downloadQuality.title.+?(children:.{1,2}\(.,.\).+?,|\(.,.\){3,4},|,.\)}},.\(.,.\)\),)//"></span><span class="pl-pds" data-code-text="'"></span></span></div></div><div data-key="86" class="react-code-text react-code-line-contents virtual" style="transform: translateY(1720px); min-height: auto;"><div id="LC87" class="react-file-line html-div" data-testid="code-cell" data-line-number="87" style="position: relative;"><span data-code-text="HIDE_DL_ICON="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text=" .BKsbV2Xl786X9a09XROH {display:none}"></span><span class="pl-pds" data-code-text="'"></span></span></div></div><div data-key="87" class="react-code-text react-code-line-contents virtual" style="transform: translateY(1740px); min-height: auto;"><div id="LC88" class="react-file-line html-div" data-testid="code-cell" data-line-number="88" style="position: relative;"><span data-code-text="HIDE_DL_MENU="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text=" button.wC9sIed7pfp47wZbmU6m.pzkhLqffqF_4hucrVVQA {display:none}"></span><span class="pl-pds" data-code-text="'"></span></span></div></div><div data-key="88" class="react-code-text react-code-line-contents virtual" style="transform: translateY(1760px); min-height: auto;"><div id="LC89" class="react-file-line html-div" data-testid="code-cell" data-line-number="89" style="position: relative;"><span data-code-text="HIDE_VERY_HIGH="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text=" #desktop\.settings\.streamingQuality&gt;option:nth-child(5) {display:none}"></span><span class="pl-pds" data-code-text="'"></span></span></div></div><div data-key="89" class="react-code-text react-code-line-contents virtual" style="transform: translateY(1780px); min-height: auto;"><div id="LC90" class="react-file-line html-div" data-testid="code-cell" data-line-number="90" style="position: relative;"><span data-code-text=""></span></div></div><div data-key="90" class="react-code-text react-code-line-contents virtual" style="transform: translateY(1800px); min-height: auto;"><div id="LC91" class="react-file-line html-div" data-testid="code-cell" data-line-number="91" style="position: relative;"><span class="pl-c"><span class="pl-c" data-code-text="#"></span><span data-code-text=" Hide Podcasts/Episodes/Audiobooks on home screen"></span></span></div></div><div data-key="91" class="react-code-text react-code-line-contents virtual" style="transform: translateY(1820px); min-height: auto;"><div id="LC92" class="react-file-line html-div" data-testid="code-cell" data-line-number="92" style="position: relative;"><span data-code-text="HIDE_PODCASTS="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="s|withQueryParameters\(.\)\{return this.queryParameters=.,this}|withQueryParameters(e){return this.queryParameters=(e.types?{...e, types: e.types.split(&quot;,&quot;).filter(_ =&gt; ![&quot;episode&quot;,&quot;show&quot;].includes(_)).join(&quot;,&quot;)}:e),this}|"></span><span class="pl-pds" data-code-text="'"></span></span></div></div><div data-key="92" class="react-code-text react-code-line-contents virtual" style="transform: translateY(1840px); min-height: auto;"><div id="LC93" class="react-file-line html-div" data-testid="code-cell" data-line-number="93" style="position: relative;"><span data-code-text="HIDE_PODCASTS2="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="s/(!Array.isArray\(.\)\|\|.===..length)/$1||e.children[0].key.includes("></span><span class="pl-pds" data-code-text="'"></span></span><span class="pl-cce" data-code-text="\'"></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="episode"></span><span class="pl-pds" data-code-text="'"></span></span><span class="pl-cce" data-code-text="\'"></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text=")||e.children[0].key.includes("></span><span class="pl-pds" data-code-text="'"></span></span><span class="pl-cce" data-code-text="\'"></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="show"></span><span class="pl-pds" data-code-text="'"></span></span><span class="pl-cce" data-code-text="\'"></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text=")/"></span><span class="pl-pds" data-code-text="'"></span></span></div></div><div data-key="93" class="react-code-text react-code-line-contents virtual" style="transform: translateY(1860px); min-height: auto;"><div id="LC94" class="react-file-line html-div" data-testid="code-cell" data-line-number="94" style="position: relative;"><span data-code-text="HIDE_PODCASTS3="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="s/(!Array.isArray\(.\)\|\|.===..length)/$1||e[0].key.includes("></span><span class="pl-pds" data-code-text="'"></span></span><span class="pl-cce" data-code-text="\'"></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="episode"></span><span class="pl-pds" data-code-text="'"></span></span><span class="pl-cce" data-code-text="\'"></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text=")||e[0].key.includes("></span><span class="pl-pds" data-code-text="'"></span></span><span class="pl-cce" data-code-text="\'"></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="show"></span><span class="pl-pds" data-code-text="'"></span></span><span class="pl-cce" data-code-text="\'"></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text=")/"></span><span class="pl-pds" data-code-text="'"></span></span></div></div><div data-key="94" class="react-code-text react-code-line-contents virtual" style="transform: translateY(1880px); min-height: auto;"><div id="LC95" class="react-file-line html-div" data-testid="code-cell" data-line-number="95" style="position: relative;"><span data-code-text=""></span></div></div><div data-key="95" class="react-code-text react-code-line-contents virtual" style="transform: translateY(1900px); min-height: auto;"><div id="LC96" class="react-file-line html-div" data-testid="code-cell" data-line-number="96" style="position: relative;"><span class="pl-c"><span class="pl-c" data-code-text="#"></span><span data-code-text=" Log-related regex"></span></span></div></div><div data-key="96" class="react-code-text react-code-line-contents virtual" style="transform: translateY(1920px); min-height: auto;"><div id="LC97" class="react-file-line html-div" data-testid="code-cell" data-line-number="97" style="position: relative;"><span data-code-text="LOG_1="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="s|sp://logging/v3/\w+||g"></span><span class="pl-pds" data-code-text="'"></span></span></div></div><div data-key="97" class="react-code-text react-code-line-contents virtual" style="transform: translateY(1940px); min-height: auto;"><div id="LC98" class="react-file-line html-div" data-testid="code-cell" data-line-number="98" style="position: relative;"><span data-code-text="LOG_SENTRY="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="s|this\.getStackTop\(\)\.client=e|return;$&amp;|"></span><span class="pl-pds" data-code-text="'"></span></span></div></div><div data-key="98" class="react-code-text react-code-line-contents virtual" style="transform: translateY(1960px); min-height: auto;"><div id="LC99" class="react-file-line html-div" data-testid="code-cell" data-line-number="99" style="position: relative;"><span data-code-text=""></span></div></div><div data-key="99" class="react-code-text react-code-line-contents virtual" style="transform: translateY(1980px); min-height: auto;"><div id="LC100" class="react-file-line html-div" data-testid="code-cell" data-line-number="100" style="position: relative;"><span class="pl-c"><span class="pl-c" data-code-text="#"></span><span data-code-text=" Spotify Connect unlock / UI"></span></span></div></div><div data-key="100" class="react-code-text react-code-line-contents virtual" style="transform: translateY(2000px); min-height: auto;"><div id="LC101" class="react-file-line html-div" data-testid="code-cell" data-line-number="101" style="position: relative;"><span data-code-text="CONNECT_OLD_1="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="s| connect-device-list-item--disabled||"></span><span class="pl-pds" data-code-text="'"></span></span><span data-code-text=" "></span><span class="pl-c"><span class="pl-c" data-code-text="#"></span><span data-code-text=" 1.1.70.610+"></span></span></div></div><div data-key="101" class="react-code-text react-code-line-contents virtual" style="transform: translateY(2020px); min-height: auto;"><div id="LC102" class="react-file-line html-div" data-testid="code-cell" data-line-number="102" style="position: relative;"><span data-code-text="CONNECT_OLD_2="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="s|connect-picker.unavailable-to-control|spotify-connect|"></span><span class="pl-pds" data-code-text="'"></span></span><span data-code-text=" "></span><span class="pl-c"><span class="pl-c" data-code-text="#"></span><span data-code-text=" 1.1.70.610+"></span></span></div></div><div data-key="102" class="react-code-text react-code-line-contents virtual" style="transform: translateY(2040px); min-height: auto;"><div id="LC103" class="react-file-line html-div" data-testid="code-cell" data-line-number="103" style="position: relative;"><span data-code-text="CONNECT_OLD_3="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="s|(className:.,disabled:)(..)|$1false|"></span><span class="pl-pds" data-code-text="'"></span></span><span data-code-text=" "></span><span class="pl-c"><span class="pl-c" data-code-text="#"></span><span data-code-text=" 1.1.70.610+"></span></span></div></div><div data-key="103" class="react-code-text react-code-line-contents virtual" style="transform: translateY(2060px); min-height: auto;"><div id="LC104" class="react-file-line html-div" data-testid="code-cell" data-line-number="104" style="position: relative;"><span data-code-text="CONNECT_NEW="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="s/return (..isDisabled)(\?(..createElement|\(.{1,10}\))\(..,)/return false$2/"></span><span class="pl-pds" data-code-text="'"></span></span><span data-code-text=" "></span><span class="pl-c"><span class="pl-c" data-code-text="#"></span><span data-code-text=" 1.1.91.824+"></span></span></div></div><div data-key="104" class="react-code-text react-code-line-contents virtual" style="transform: translateY(2080px); min-height: auto;"><div id="LC105" class="react-file-line html-div" data-testid="code-cell" data-line-number="105" style="position: relative;"><span data-code-text="DEVICE_PICKER_NEW="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="s|(Enable showing a new and improved device picker UI&quot;,default:)(!1)|$1true|"></span><span class="pl-pds" data-code-text="'"></span></span><span data-code-text=" "></span><span class="pl-c"><span class="pl-c" data-code-text="#"></span><span data-code-text=" 1.1.90.855 - 1.1.95.893"></span></span></div></div><div data-key="105" class="react-code-text react-code-line-contents virtual" style="transform: translateY(2100px); min-height: auto;"><div id="LC106" class="react-file-line html-div" data-testid="code-cell" data-line-number="106" style="position: relative;"><span data-code-text="DEVICE_PICKER_OLD="></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="s|(Enable showing a new and improved device picker UI&quot;,default:)(!0)|$1false|"></span><span class="pl-pds" data-code-text="'"></span></span><span data-code-text=" "></span><span class="pl-c"><span class="pl-c" data-code-text="#"></span><span data-code-text=" 1.1.96.783 - 1.1.97.962"></span></span></div></div><div data-key="106" class="react-code-text react-code-line-contents virtual" style="transform: translateY(2120px); min-height: auto;"><div id="LC107" class="react-file-line html-div" data-testid="code-cell" data-line-number="107" style="position: relative;"><span data-code-text=""></span></div></div><div data-key="107" class="react-code-text react-code-line-contents virtual" style="transform: translateY(2140px); min-height: auto;"><div id="LC108" class="react-file-line html-div" data-testid="code-cell" data-line-number="108" style="position: relative;"><span class="pl-c"><span class="pl-c" data-code-text="#"></span><span data-code-text=" Credits"></span></span></div></div><div data-key="108" class="react-code-text react-code-line-contents virtual" style="transform: translateY(2160px); min-height: auto;"><div id="LC109" class="react-file-line html-div" data-testid="code-cell" data-line-number="109" style="position: relative;"><span class="pl-c1" data-code-text="echo"></span></div></div><div data-key="109" class="react-code-text react-code-line-contents virtual" style="transform: translateY(2180px); min-height: auto;"><div id="LC110" class="react-file-line html-div" data-testid="code-cell" data-line-number="110" style="position: relative;"><span class="pl-c1" data-code-text="echo"></span><span data-code-text=" "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span data-code-text="**************************"></span><span class="pl-pds" data-code-text="&quot;"></span></span></div></div><div data-key="110" class="react-code-text react-code-line-contents virtual" style="transform: translateY(2200px); min-height: auto;"><div id="LC111" class="react-file-line html-div" data-testid="code-cell" data-line-number="111" style="position: relative;"><span class="pl-c1" data-code-text="echo"></span><span data-code-text=" "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span data-code-text="SpotX-Linux by @SpotX-CLI"></span><span class="pl-pds" data-code-text="&quot;"></span></span></div></div><div data-key="111" class="react-code-text react-code-line-contents virtual" style="transform: translateY(2220px); min-height: auto;"><div id="LC112" class="react-file-line html-div" data-testid="code-cell" data-line-number="112" style="position: relative;"><span class="pl-c1" data-code-text="echo"></span><span data-code-text=" "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span data-code-text="**************************"></span><span class="pl-pds" data-code-text="&quot;"></span></span></div></div><div data-key="112" class="react-code-text react-code-line-contents virtual" style="transform: translateY(2240px); min-height: auto;"><div id="LC113" class="react-file-line html-div" data-testid="code-cell" data-line-number="113" style="position: relative;"><span class="pl-c1" data-code-text="echo"></span></div></div><div data-key="113" class="react-code-text react-code-line-contents virtual" style="transform: translateY(2260px); min-height: auto;"><div id="LC114" class="react-file-line html-div" data-testid="code-cell" data-line-number="114" style="position: relative;"><span data-code-text=""></span></div></div><div data-key="114" class="react-code-text react-code-line-contents virtual" style="transform: translateY(2280px); min-height: auto;"><div id="LC115" class="react-file-line html-div" data-testid="code-cell" data-line-number="115" style="position: relative;"><span class="pl-c"><span class="pl-c" data-code-text="#"></span><span data-code-text=" Report SpotX version"></span></span></div></div><div data-key="115" class="react-code-text react-code-line-contents virtual" style="transform: translateY(2300px); min-height: auto;"><div id="LC116" class="react-file-line html-div" data-testid="code-cell" data-line-number="116" style="position: relative;"><span class="pl-c1" data-code-text="echo"></span><span data-code-text=" -e "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span data-code-text="SpotX-Linux version: "></span><span class="pl-smi" data-code-text="${SPOTX_VERSION}"></span><span data-code-text="\n"></span><span class="pl-pds" data-code-text="&quot;"></span></span></div></div><div data-key="116" class="react-code-text react-code-line-contents virtual" style="transform: translateY(2320px); min-height: auto;"><div id="LC117" class="react-file-line html-div" data-testid="code-cell" data-line-number="117" style="position: relative;"><span data-code-text=""></span></div></div><div data-key="117" class="react-code-text react-code-line-contents virtual" style="transform: translateY(2340px); min-height: auto;"><div id="LC118" class="react-file-line html-div" data-testid="code-cell" data-line-number="118" style="position: relative;"><span class="pl-c"><span class="pl-c" data-code-text="#"></span><span data-code-text=" Locate install directory"></span></span></div></div><div data-key="118" class="react-code-text react-code-line-contents virtual" style="transform: translateY(2360px); min-height: auto;"><div id="LC119" class="react-file-line html-div" data-testid="code-cell" data-line-number="119" style="position: relative;"><span class="pl-k" data-code-text="if"></span><span data-code-text=" [ "></span><span class="pl-k" data-code-text="-z"></span><span data-code-text=" "></span><span class="pl-smi" data-code-text="${INSTALL_PATH+x}"></span><span data-code-text=" ]"></span><span class="pl-k" data-code-text=";"></span><span data-code-text=" "></span><span class="pl-k" data-code-text="then"></span></div></div><div data-key="119" class="react-code-text react-code-line-contents virtual" style="transform: translateY(2380px); min-height: auto;"><div id="LC120" class="react-file-line html-div" data-testid="code-cell" data-line-number="120" style="position: relative;"><span data-code-text="  INSTALL_PATH="></span><span class="pl-s"><span class="pl-pds" data-code-text="$("></span><span data-code-text="readlink -e "></span><span class="pl-s"><span class="pl-pds" data-code-text="`"></span><span data-code-text="type -p spotify"></span><span class="pl-pds" data-code-text="`"></span></span><span data-code-text=" "></span><span class="pl-k" data-code-text="2&gt;"></span><span data-code-text="/dev/null "></span><span class="pl-k" data-code-text="|"></span><span data-code-text=" rev "></span><span class="pl-k" data-code-text="|"></span><span data-code-text=" cut -d/ -f2- "></span><span class="pl-k" data-code-text="|"></span><span data-code-text=" rev"></span><span class="pl-pds" data-code-text=")"></span></span></div></div><div data-key="120" class="react-code-text react-code-line-contents virtual" style="transform: translateY(2400px); min-height: auto;"><div id="LC121" class="react-file-line html-div" data-testid="code-cell" data-line-number="121" style="position: relative;"><span data-code-text="  "></span><span class="pl-k" data-code-text="if"></span><span data-code-text=" [[ "></span><span class="pl-k" data-code-text="-d"></span><span data-code-text=" "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span class="pl-smi" data-code-text="${INSTALL_PATH}"></span><span class="pl-pds" data-code-text="&quot;"></span></span><span data-code-text=" "></span><span class="pl-k" data-code-text="&amp;&amp;"></span><span data-code-text=" "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span class="pl-smi" data-code-text="${INSTALL_PATH}"></span><span class="pl-pds" data-code-text="&quot;"></span></span><span data-code-text=" "></span><span class="pl-k" data-code-text="!="></span><span data-code-text=" "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span data-code-text="/usr/bin"></span><span class="pl-pds" data-code-text="&quot;"></span></span><span data-code-text=" ]]"></span><span class="pl-k" data-code-text=";"></span><span data-code-text=" "></span><span class="pl-k" data-code-text="then"></span></div></div><div data-key="121" class="react-code-text react-code-line-contents virtual" style="transform: translateY(2420px); min-height: auto;"><div id="LC122" class="react-file-line html-div" data-testid="code-cell" data-line-number="122" style="position: relative;"><span data-code-text="    "></span><span class="pl-c1" data-code-text="echo"></span><span data-code-text=" "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span data-code-text="Spotify directory found in PATH: "></span><span class="pl-smi" data-code-text="${INSTALL_PATH}"></span><span class="pl-pds" data-code-text="&quot;"></span></span></div></div><div data-key="122" class="react-code-text react-code-line-contents virtual" style="transform: translateY(2440px); min-height: auto;"><div id="LC123" class="react-file-line html-div" data-testid="code-cell" data-line-number="123" style="position: relative;"><span data-code-text="  "></span><span class="pl-k" data-code-text="elif"></span><span data-code-text=" [[ "></span><span class="pl-k" data-code-text="!"></span><span data-code-text=" "></span><span class="pl-k" data-code-text="-d"></span><span data-code-text=" "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span class="pl-smi" data-code-text="${INSTALL_PATH}"></span><span class="pl-pds" data-code-text="&quot;"></span></span><span data-code-text=" ]]"></span><span class="pl-k" data-code-text=";"></span><span data-code-text=" "></span><span class="pl-k" data-code-text="then"></span></div></div><div data-key="123" class="react-code-text react-code-line-contents virtual" style="transform: translateY(2460px); min-height: auto;"><div id="LC124" class="react-file-line html-div" data-testid="code-cell" data-line-number="124" style="position: relative;"><span data-code-text="    "></span><span class="pl-c1" data-code-text="echo"></span><span data-code-text=" -e "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span data-code-text="\nSpotify not found in PATH. Searching for Spotify directory..."></span><span class="pl-pds" data-code-text="&quot;"></span></span></div></div><div data-key="124" class="react-code-text react-code-line-contents virtual" style="transform: translateY(2480px); min-height: auto;"><div id="LC125" class="react-file-line html-div" data-testid="code-cell" data-line-number="125" style="position: relative;"><span data-code-text="    INSTALL_PATH="></span><span class="pl-s"><span class="pl-pds" data-code-text="$("></span><span data-code-text="timeout 10 find / -type f -path "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span data-code-text="*/spotify*Apps/*"></span><span class="pl-pds" data-code-text="&quot;"></span></span><span data-code-text=" -name "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span data-code-text="xpui.spa"></span><span class="pl-pds" data-code-text="&quot;"></span></span><span data-code-text=" -size -7M -size +3M -print -quit "></span><span class="pl-k" data-code-text="2&gt;"></span><span data-code-text="/dev/null "></span><span class="pl-k" data-code-text="|"></span><span data-code-text=" rev "></span><span class="pl-k" data-code-text="|"></span><span data-code-text=" cut -d/ -f3- "></span><span class="pl-k" data-code-text="|"></span><span data-code-text=" rev"></span><span class="pl-pds" data-code-text=")"></span></span></div></div><div data-key="125" class="react-code-text react-code-line-contents virtual" style="transform: translateY(2500px); min-height: auto;"><div id="LC126" class="react-file-line html-div" data-testid="code-cell" data-line-number="126" style="position: relative;"><span data-code-text="    "></span><span class="pl-k" data-code-text="if"></span><span data-code-text=" [[ "></span><span class="pl-k" data-code-text="-d"></span><span data-code-text=" "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span class="pl-smi" data-code-text="${INSTALL_PATH}"></span><span class="pl-pds" data-code-text="&quot;"></span></span><span data-code-text=" ]]"></span><span class="pl-k" data-code-text=";"></span><span data-code-text=" "></span><span class="pl-k" data-code-text="then"></span></div></div><div data-key="126" class="react-code-text react-code-line-contents virtual" style="transform: translateY(2520px); min-height: auto;"><div id="LC127" class="react-file-line html-div" data-testid="code-cell" data-line-number="127" style="position: relative;"><span data-code-text="      "></span><span class="pl-c1" data-code-text="echo"></span><span data-code-text=" "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span data-code-text="Spotify directory found: "></span><span class="pl-smi" data-code-text="${INSTALL_PATH}"></span><span class="pl-pds" data-code-text="&quot;"></span></span></div></div><div data-key="127" class="react-code-text react-code-line-contents virtual" style="transform: translateY(2540px); min-height: auto;"><div id="LC128" class="react-file-line html-div" data-testid="code-cell" data-line-number="128" style="position: relative;"><span data-code-text="    "></span><span class="pl-k" data-code-text="elif"></span><span data-code-text=" [[ "></span><span class="pl-k" data-code-text="!"></span><span data-code-text=" "></span><span class="pl-k" data-code-text="-d"></span><span data-code-text=" "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span class="pl-smi" data-code-text="${INSTALL_PATH}"></span><span class="pl-pds" data-code-text="&quot;"></span></span><span data-code-text=" ]]"></span><span class="pl-k" data-code-text=";"></span><span data-code-text=" "></span><span class="pl-k" data-code-text="then"></span></div></div><div data-key="128" class="react-code-text react-code-line-contents virtual" style="transform: translateY(2560px); min-height: auto;"><div id="LC129" class="react-file-line html-div" data-testid="code-cell" data-line-number="129" style="position: relative;"><span data-code-text="      "></span><span class="pl-c1" data-code-text="echo"></span><span data-code-text=" -e "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span data-code-text="Spotify directory not found. Set directory path with -P flag.\nExiting...\n"></span><span class="pl-pds" data-code-text="&quot;"></span></span></div></div><div data-key="129" class="react-code-text react-code-line-contents virtual" style="transform: translateY(2580px); min-height: auto;"><div id="LC130" class="react-file-line html-div" data-testid="code-cell" data-line-number="130" style="position: relative;"><span data-code-text="      "></span><span class="pl-c1" data-code-text="exit"></span><span class="pl-k" data-code-text=";"></span><span data-code-text=" "></span><span class="pl-k" data-code-text="fi"></span></div></div><div data-key="130" class="react-code-text react-code-line-contents virtual" style="transform: translateY(2600px); min-height: auto;"><div id="LC131" class="react-file-line html-div" data-testid="code-cell" data-line-number="131" style="position: relative;"><span data-code-text="  "></span><span class="pl-k" data-code-text="elif"></span><span data-code-text=" [[ "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span class="pl-smi" data-code-text="${INSTALL_PATH}"></span><span class="pl-pds" data-code-text="&quot;"></span></span><span data-code-text=" "></span><span class="pl-k" data-code-text="=="></span><span data-code-text=" "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span data-code-text="/usr/bin"></span><span class="pl-pds" data-code-text="&quot;"></span></span><span data-code-text=" ]]"></span><span class="pl-k" data-code-text=";"></span><span data-code-text=" "></span><span class="pl-k" data-code-text="then"></span></div></div><div data-key="131" class="react-code-text react-code-line-contents virtual" style="transform: translateY(2620px); min-height: auto;"><div id="LC132" class="react-file-line html-div" data-testid="code-cell" data-line-number="132" style="position: relative;"><span data-code-text="    "></span><span class="pl-c1" data-code-text="echo"></span><span data-code-text=" -e "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span data-code-text="\nSpotify PATH is set to /usr/bin, searching for Spotify directory..."></span><span class="pl-pds" data-code-text="&quot;"></span></span></div></div><div data-key="132" class="react-code-text react-code-line-contents virtual" style="transform: translateY(2640px); min-height: auto;"><div id="LC133" class="react-file-line html-div" data-testid="code-cell" data-line-number="133" style="position: relative;"><span data-code-text="    INSTALL_PATH="></span><span class="pl-s"><span class="pl-pds" data-code-text="$("></span><span data-code-text="timeout 10 find / -type f -path "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span data-code-text="*/spotify*Apps/*"></span><span class="pl-pds" data-code-text="&quot;"></span></span><span data-code-text=" -name "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span data-code-text="xpui.spa"></span><span class="pl-pds" data-code-text="&quot;"></span></span><span data-code-text=" -size -7M -size +3M -print -quit "></span><span class="pl-k" data-code-text="2&gt;"></span><span data-code-text="/dev/null "></span><span class="pl-k" data-code-text="|"></span><span data-code-text=" rev "></span><span class="pl-k" data-code-text="|"></span><span data-code-text=" cut -d/ -f3- "></span><span class="pl-k" data-code-text="|"></span><span data-code-text=" rev"></span><span class="pl-pds" data-code-text=")"></span></span></div></div><div data-key="133" class="react-code-text react-code-line-contents virtual" style="transform: translateY(2660px); min-height: auto;"><div id="LC134" class="react-file-line html-div" data-testid="code-cell" data-line-number="134" style="position: relative;"><span data-code-text="    "></span><span class="pl-k" data-code-text="if"></span><span data-code-text=" [[ "></span><span class="pl-k" data-code-text="-d"></span><span data-code-text=" "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span class="pl-smi" data-code-text="${INSTALL_PATH}"></span><span class="pl-pds" data-code-text="&quot;"></span></span><span data-code-text=" "></span><span class="pl-k" data-code-text="&amp;&amp;"></span><span data-code-text=" "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span class="pl-smi" data-code-text="${INSTALL_PATH}"></span><span class="pl-pds" data-code-text="&quot;"></span></span><span data-code-text=" "></span><span class="pl-k" data-code-text="!="></span><span data-code-text=" "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span data-code-text="/usr/bin"></span><span class="pl-pds" data-code-text="&quot;"></span></span><span data-code-text=" ]]"></span><span class="pl-k" data-code-text=";"></span><span data-code-text=" "></span><span class="pl-k" data-code-text="then"></span></div></div><div data-key="134" class="react-code-text react-code-line-contents virtual" style="transform: translateY(2680px); min-height: auto;"><div id="LC135" class="react-file-line html-div" data-testid="code-cell" data-line-number="135" style="position: relative;"><span data-code-text="      "></span><span class="pl-c1" data-code-text="echo"></span><span data-code-text=" "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span data-code-text="Spotify directory found: "></span><span class="pl-smi" data-code-text="${INSTALL_PATH}"></span><span class="pl-pds" data-code-text="&quot;"></span></span></div></div><div data-key="135" class="react-code-text react-code-line-contents virtual" style="transform: translateY(2700px); min-height: auto;"><div id="LC136" class="react-file-line html-div" data-testid="code-cell" data-line-number="136" style="position: relative;"><span data-code-text="    "></span><span class="pl-k" data-code-text="elif"></span><span data-code-text=" [[ "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span class="pl-smi" data-code-text="${INSTALL_PATH}"></span><span class="pl-pds" data-code-text="&quot;"></span></span><span data-code-text=" "></span><span class="pl-k" data-code-text="=="></span><span data-code-text=" "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span data-code-text="/usr/bin"></span><span class="pl-pds" data-code-text="&quot;"></span></span><span data-code-text=" ]] "></span><span class="pl-k" data-code-text="||"></span><span data-code-text=" [[ "></span><span class="pl-k" data-code-text="!"></span><span data-code-text=" "></span><span class="pl-k" data-code-text="-d"></span><span data-code-text=" "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span class="pl-smi" data-code-text="${INSTALL_PATH}"></span><span class="pl-pds" data-code-text="&quot;"></span></span><span data-code-text=" ]]"></span><span class="pl-k" data-code-text=";"></span><span data-code-text=" "></span><span class="pl-k" data-code-text="then"></span></div></div><div data-key="136" class="react-code-text react-code-line-contents virtual" style="transform: translateY(2720px); min-height: auto;"><div id="LC137" class="react-file-line html-div" data-testid="code-cell" data-line-number="137" style="position: relative;"><span data-code-text="      "></span><span class="pl-c1" data-code-text="echo"></span><span data-code-text=" -e "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span data-code-text="Spotify directory not found. Set directory path with -P flag.\nExiting...\n"></span><span class="pl-pds" data-code-text="&quot;"></span></span></div></div><div data-key="137" class="react-code-text react-code-line-contents virtual" style="transform: translateY(2740px); min-height: auto;"><div id="LC138" class="react-file-line html-div" data-testid="code-cell" data-line-number="138" style="position: relative;"><span data-code-text="      "></span><span class="pl-c1" data-code-text="exit"></span><span class="pl-k" data-code-text=";"></span><span data-code-text=" "></span><span class="pl-k" data-code-text="fi"></span><span class="pl-k" data-code-text=";"></span><span data-code-text=" "></span><span class="pl-k" data-code-text="fi"></span></div></div><div data-key="138" class="react-code-text react-code-line-contents virtual" style="transform: translateY(2760px); min-height: auto;"><div id="LC139" class="react-file-line html-div" data-testid="code-cell" data-line-number="139" style="position: relative;"><span class="pl-k" data-code-text="else"></span></div></div><div data-key="139" class="react-code-text react-code-line-contents virtual" style="transform: translateY(2780px); min-height: auto;"><div id="LC140" class="react-file-line html-div" data-testid="code-cell" data-line-number="140" style="position: relative;"><span data-code-text="  "></span><span class="pl-k" data-code-text="if"></span><span data-code-text=" [[ "></span><span class="pl-k" data-code-text="!"></span><span data-code-text=" "></span><span class="pl-k" data-code-text="-d"></span><span data-code-text=" "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span class="pl-smi" data-code-text="${INSTALL_PATH}"></span><span class="pl-pds" data-code-text="&quot;"></span></span><span data-code-text=" ]]"></span><span class="pl-k" data-code-text=";"></span><span data-code-text=" "></span><span class="pl-k" data-code-text="then"></span></div></div><div data-key="140" class="react-code-text react-code-line-contents virtual" style="transform: translateY(2800px); min-height: auto;"><div id="LC141" class="react-file-line html-div" data-testid="code-cell" data-line-number="141" style="position: relative;"><span data-code-text="    "></span><span class="pl-c1" data-code-text="echo"></span><span data-code-text=" -e "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span data-code-text="Directory path set by -P was not found.\nExiting...\n"></span><span class="pl-pds" data-code-text="&quot;"></span></span></div></div><div data-key="141" class="react-code-text react-code-line-contents virtual" style="transform: translateY(2820px); min-height: auto;"><div id="LC142" class="react-file-line html-div" data-testid="code-cell" data-line-number="142" style="position: relative;"><span data-code-text="    "></span><span class="pl-c1" data-code-text="exit"></span></div></div><div data-key="142" class="react-code-text react-code-line-contents virtual" style="transform: translateY(2840px); min-height: auto;"><div id="LC143" class="react-file-line html-div" data-testid="code-cell" data-line-number="143" style="position: relative;"><span data-code-text="  "></span><span class="pl-k" data-code-text="elif"></span><span data-code-text=" [[ "></span><span class="pl-k" data-code-text="!"></span><span data-code-text=" "></span><span class="pl-k" data-code-text="-f"></span><span data-code-text=" "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span class="pl-smi" data-code-text="${INSTALL_PATH}"></span><span data-code-text="/Apps/xpui.spa"></span><span class="pl-pds" data-code-text="&quot;"></span></span><span data-code-text=" ]]"></span><span class="pl-k" data-code-text=";"></span><span data-code-text=" "></span><span class="pl-k" data-code-text="then"></span></div></div><div data-key="143" class="react-code-text react-code-line-contents virtual" style="transform: translateY(2860px); min-height: auto;"><div id="LC144" class="react-file-line html-div" data-testid="code-cell" data-line-number="144" style="position: relative;"><span data-code-text="    "></span><span class="pl-c1" data-code-text="echo"></span><span data-code-text=" -e "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span data-code-text="No xpui found in directory provided with -P.\nPlease confirm directory and try again or re-install Spotify.\nExiting...\n"></span><span class="pl-pds" data-code-text="&quot;"></span></span></div></div><div data-key="144" class="react-code-text react-code-line-contents virtual" style="transform: translateY(2880px); min-height: auto;"><div id="LC145" class="react-file-line html-div" data-testid="code-cell" data-line-number="145" style="position: relative;"><span data-code-text="    "></span><span class="pl-c1" data-code-text="exit"></span><span class="pl-k" data-code-text=";"></span><span data-code-text=" "></span><span class="pl-k" data-code-text="fi"></span><span class="pl-k" data-code-text=";"></span><span data-code-text=" "></span><span class="pl-k" data-code-text="fi"></span></div></div><div data-key="145" class="react-code-text react-code-line-contents virtual" style="transform: translateY(2900px); min-height: auto;"><div id="LC146" class="react-file-line html-div" data-testid="code-cell" data-line-number="146" style="position: relative;"><span data-code-text=""></span></div></div><div data-key="146" class="react-code-text react-code-line-contents virtual" style="transform: translateY(2920px); min-height: auto;"><div id="LC147" class="react-file-line html-div" data-testid="code-cell" data-line-number="147" style="position: relative;"><span class="pl-c"><span class="pl-c" data-code-text="#"></span><span data-code-text=" Find client version"></span></span></div></div><div data-key="147" class="react-code-text react-code-line-contents virtual" style="transform: translateY(2940px); min-height: auto;"><div id="LC148" class="react-file-line html-div" data-testid="code-cell" data-line-number="148" style="position: relative;"><span data-code-text="CLIENT_VERSION="></span><span class="pl-s"><span class="pl-pds" data-code-text="$("></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span class="pl-smi" data-code-text="${INSTALL_PATH}"></span><span class="pl-pds" data-code-text="&quot;"></span></span><span data-code-text="/spotify --version "></span><span class="pl-k" data-code-text="|"></span><span data-code-text=" cut -dn -f2- "></span><span class="pl-k" data-code-text="|"></span><span data-code-text=" rev "></span><span class="pl-k" data-code-text="|"></span><span data-code-text=" cut -d. -f2- "></span><span class="pl-k" data-code-text="|"></span><span data-code-text=" rev"></span><span class="pl-pds" data-code-text=")"></span></span></div></div><div data-key="148" class="react-code-text react-code-line-contents virtual" style="transform: translateY(2960px); min-height: auto;"><div id="LC149" class="react-file-line html-div" data-testid="code-cell" data-line-number="149" style="position: relative;"><span data-code-text=""></span></div></div><div data-key="149" class="react-code-text react-code-line-contents virtual" style="transform: translateY(2980px); min-height: auto;"><div id="LC150" class="react-file-line html-div" data-testid="code-cell" data-line-number="150" style="position: relative;"><span class="pl-c"><span class="pl-c" data-code-text="#"></span><span data-code-text=" Version function for version comparison"></span></span></div></div><div data-key="150" class="react-code-text react-code-line-contents virtual" style="transform: translateY(3000px); min-height: auto;"><div id="LC151" class="react-file-line html-div" data-testid="code-cell" data-line-number="151" style="position: relative;"><span class="pl-k" data-code-text="function"></span><span data-code-text=" "></span><span class="pl-en" data-code-text="ver"></span><span data-code-text=" { "></span><span class="pl-c1" data-code-text="echo"></span><span data-code-text=" "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span class="pl-smi" data-code-text="$@"></span><span class="pl-pds" data-code-text="&quot;"></span></span><span data-code-text=" "></span><span class="pl-k" data-code-text="|"></span><span data-code-text=" awk -F. "></span><span class="pl-s"><span class="pl-pds" data-code-text="'"></span><span data-code-text="{ printf(&quot;%d%03d%03d%03d\n&quot;, $1,$2,$3,$4); }"></span><span class="pl-pds" data-code-text="'"></span></span><span class="pl-k" data-code-text=";"></span><span data-code-text=" }"></span></div></div><div data-key="151" class="react-code-text react-code-line-contents virtual" style="transform: translateY(3020px); min-height: auto;"><div id="LC152" class="react-file-line html-div" data-testid="code-cell" data-line-number="152" style="position: relative;"><span data-code-text=""></span></div></div><div data-key="152" class="react-code-text react-code-line-contents virtual" style="transform: translateY(3040px); min-height: auto;"><div id="LC153" class="react-file-line html-div" data-testid="code-cell" data-line-number="153" style="position: relative;"><span class="pl-c"><span class="pl-c" data-code-text="#"></span><span data-code-text=" Report Spotify version"></span></span></div></div><div data-key="153" class="react-code-text react-code-line-contents virtual" style="transform: translateY(3060px); min-height: auto;"><div id="LC154" class="react-file-line html-div" data-testid="code-cell" data-line-number="154" style="position: relative;"><span class="pl-c1" data-code-text="echo"></span><span data-code-text=" -e "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span data-code-text="\nSpotify version: "></span><span class="pl-smi" data-code-text="${CLIENT_VERSION}"></span><span data-code-text="\n"></span><span class="pl-pds" data-code-text="&quot;"></span></span></div></div><div data-key="154" class="react-code-text react-code-line-contents virtual" style="transform: translateY(3080px); min-height: auto;"><div id="LC155" class="react-file-line html-div" data-testid="code-cell" data-line-number="155" style="position: relative;"><span data-code-text="     "></span></div></div><div data-key="155" class="react-code-text react-code-line-contents virtual" style="transform: translateY(3100px); min-height: auto;"><div id="LC156" class="react-file-line html-div" data-testid="code-cell" data-line-number="156" style="position: relative;"><span class="pl-c"><span class="pl-c" data-code-text="#"></span><span data-code-text=" Path vars"></span></span></div></div><div data-key="156" class="react-code-text react-code-line-contents virtual" style="transform: translateY(3120px); min-height: auto;"><div id="LC157" class="react-file-line html-div" data-testid="code-cell" data-line-number="157" style="position: relative;"><span data-code-text="CACHE_PATH="></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span class="pl-smi" data-code-text="${HOME}"></span><span data-code-text="/.cache/spotify/"></span><span class="pl-pds" data-code-text="&quot;"></span></span></div></div><div data-key="157" class="react-code-text react-code-line-contents virtual" style="transform: translateY(3140px); min-height: auto;"><div id="LC158" class="react-file-line html-div" data-testid="code-cell" data-line-number="158" style="position: relative;"><span data-code-text="XPUI_PATH="></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span class="pl-smi" data-code-text="${INSTALL_PATH}"></span><span data-code-text="/Apps"></span><span class="pl-pds" data-code-text="&quot;"></span></span></div></div><div data-key="158" class="react-code-text react-code-line-contents virtual" style="transform: translateY(3160px); min-height: auto;"><div id="LC159" class="react-file-line html-div" data-testid="code-cell" data-line-number="159" style="position: relative;"><span data-code-text="XPUI_DIR="></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span class="pl-smi" data-code-text="${XPUI_PATH}"></span><span data-code-text="/xpui"></span><span class="pl-pds" data-code-text="&quot;"></span></span></div></div><div data-key="159" class="react-code-text react-code-line-contents virtual" style="transform: translateY(3180px); min-height: auto;"><div id="LC160" class="react-file-line html-div" data-testid="code-cell" data-line-number="160" style="position: relative;"><span data-code-text="XPUI_BAK="></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span class="pl-smi" data-code-text="${XPUI_PATH}"></span><span data-code-text="/xpui.bak"></span><span class="pl-pds" data-code-text="&quot;"></span></span></div></div><div data-key="160" class="react-code-text react-code-line-contents virtual" style="transform: translateY(3200px); min-height: auto;"><div id="LC161" class="react-file-line html-div" data-testid="code-cell" data-line-number="161" style="position: relative;"><span data-code-text="XPUI_SPA="></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span class="pl-smi" data-code-text="${XPUI_PATH}"></span><span data-code-text="/xpui.spa"></span><span class="pl-pds" data-code-text="&quot;"></span></span></div></div><div data-key="161" class="react-code-text react-code-line-contents virtual" style="transform: translateY(3220px); min-height: auto;"><div id="LC162" class="react-file-line html-div" data-testid="code-cell" data-line-number="162" style="position: relative;"><span data-code-text="XPUI_JS="></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span class="pl-smi" data-code-text="${XPUI_DIR}"></span><span data-code-text="/xpui.js"></span><span class="pl-pds" data-code-text="&quot;"></span></span></div></div><div data-key="162" class="react-code-text react-code-line-contents virtual" style="transform: translateY(3240px); min-height: auto;"><div id="LC163" class="react-file-line html-div" data-testid="code-cell" data-line-number="163" style="position: relative;"><span data-code-text="XPUI_CSS="></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span class="pl-smi" data-code-text="${XPUI_DIR}"></span><span data-code-text="/xpui.css"></span><span class="pl-pds" data-code-text="&quot;"></span></span></div></div><div data-key="163" class="react-code-text react-code-line-contents virtual" style="transform: translateY(3260px); min-height: auto;"><div id="LC164" class="react-file-line html-div" data-testid="code-cell" data-line-number="164" style="position: relative;"><span data-code-text="HOME_V2_JS="></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span class="pl-smi" data-code-text="${XPUI_DIR}"></span><span data-code-text="/home-v2.js"></span><span class="pl-pds" data-code-text="&quot;"></span></span></div></div><div data-key="164" class="react-code-text react-code-line-contents virtual" style="transform: translateY(3280px); min-height: auto;"><div id="LC165" class="react-file-line html-div" data-testid="code-cell" data-line-number="165" style="position: relative;"><span data-code-text="VENDOR_XPUI_JS="></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span class="pl-smi" data-code-text="${XPUI_DIR}"></span><span data-code-text="/vendor~xpui.js"></span><span class="pl-pds" data-code-text="&quot;"></span></span></div></div><div data-key="165" class="react-code-text react-code-line-contents virtual" style="transform: translateY(3300px); min-height: auto;"><div id="LC166" class="react-file-line html-div" data-testid="code-cell" data-line-number="166" style="position: relative;"><span data-code-text=""></span></div></div><div data-key="166" class="react-code-text react-code-line-contents virtual" style="transform: translateY(3320px); min-height: auto;"><div id="LC167" class="react-file-line html-div" data-testid="code-cell" data-line-number="167" style="position: relative;"><span class="pl-c"><span class="pl-c" data-code-text="#"></span><span data-code-text=" xpui detection"></span></span></div></div><div data-key="167" class="react-code-text react-code-line-contents virtual" style="transform: translateY(3340px); min-height: auto;"><div id="LC168" class="react-file-line html-div" data-testid="code-cell" data-line-number="168" style="position: relative;"><span class="pl-k" data-code-text="if"></span><span data-code-text=" [[ "></span><span class="pl-k" data-code-text="!"></span><span data-code-text=" "></span><span class="pl-k" data-code-text="-f"></span><span data-code-text=" "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span class="pl-smi" data-code-text="${XPUI_SPA}"></span><span class="pl-pds" data-code-text="&quot;"></span></span><span data-code-text=" ]]"></span><span class="pl-k" data-code-text=";"></span><span data-code-text=" "></span><span class="pl-k" data-code-text="then"></span></div></div><div data-key="168" class="react-code-text react-code-line-contents virtual" style="transform: translateY(3360px); min-height: auto;"><div id="LC169" class="react-file-line html-div" data-testid="code-cell" data-line-number="169" style="position: relative;"><span data-code-text="  "></span><span class="pl-c1" data-code-text="echo"></span><span data-code-text=" -e "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span data-code-text="\nxpui not found!\nReinstall Spotify then try again.\nExiting...\n"></span><span class="pl-pds" data-code-text="&quot;"></span></span></div></div><div data-key="169" class="react-code-text react-code-line-contents virtual" style="transform: translateY(3380px); min-height: auto;"><div id="LC170" class="react-file-line html-div" data-testid="code-cell" data-line-number="170" style="position: relative;"><span data-code-text="  "></span><span class="pl-c1" data-code-text="exit"></span></div></div><div data-key="170" class="react-code-text react-code-line-contents virtual" style="transform: translateY(3400px); min-height: auto;"><div id="LC171" class="react-file-line html-div" data-testid="code-cell" data-line-number="171" style="position: relative;"><span class="pl-k" data-code-text="else"></span></div></div><div data-key="171" class="react-code-text react-code-line-contents virtual" style="transform: translateY(3420px); min-height: auto;"><div id="LC172" class="react-file-line html-div" data-testid="code-cell" data-line-number="172" style="position: relative;"><span data-code-text="  "></span><span class="pl-k" data-code-text="if"></span><span data-code-text=" [[ "></span><span class="pl-k" data-code-text="!"></span><span data-code-text=" "></span><span class="pl-k" data-code-text="-w"></span><span data-code-text=" "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span class="pl-smi" data-code-text="${XPUI_PATH}"></span><span class="pl-pds" data-code-text="&quot;"></span></span><span data-code-text=" ]]"></span><span class="pl-k" data-code-text=";"></span><span data-code-text=" "></span><span class="pl-k" data-code-text="then"></span></div></div><div data-key="172" class="react-code-text react-code-line-contents virtual" style="transform: translateY(3440px); min-height: auto;"><div id="LC173" class="react-file-line html-div" data-testid="code-cell" data-line-number="173" style="position: relative;"><span data-code-text="    "></span><span class="pl-c1" data-code-text="echo"></span><span data-code-text=" -e "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span data-code-text="\nSpotX does not have write permission in Spotify directory.\nRequesting sudo permission...\n"></span><span class="pl-pds" data-code-text="&quot;"></span></span></div></div><div data-key="173" class="react-code-text react-code-line-contents virtual" style="transform: translateY(3460px); min-height: auto;"><div id="LC174" class="react-file-line html-div" data-testid="code-cell" data-line-number="174" style="position: relative;"><span data-code-text="    sudo chmod a+wr "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span class="pl-smi" data-code-text="${INSTALL_PATH}"></span><span class="pl-pds" data-code-text="&quot;"></span></span><span data-code-text=" "></span><span class="pl-k" data-code-text="&amp;&amp;"></span><span data-code-text=" sudo chmod a+wr -R "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span class="pl-smi" data-code-text="${XPUI_PATH}"></span><span class="pl-pds" data-code-text="&quot;"></span></span><span class="pl-k" data-code-text=";"></span><span data-code-text=" "></span><span class="pl-k" data-code-text="fi"></span></div></div><div data-key="174" class="react-code-text react-code-line-contents virtual" style="transform: translateY(3480px); min-height: auto;"><div id="LC175" class="react-file-line html-div" data-testid="code-cell" data-line-number="175" style="position: relative;"><span data-code-text="  "></span><span class="pl-k" data-code-text="if"></span><span data-code-text=" [[ "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span class="pl-smi" data-code-text="${FORCE_FLAG}"></span><span class="pl-pds" data-code-text="&quot;"></span></span><span data-code-text=" "></span><span class="pl-k" data-code-text="=="></span><span data-code-text=" "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span data-code-text="false"></span><span class="pl-pds" data-code-text="&quot;"></span></span><span data-code-text=" ]]"></span><span class="pl-k" data-code-text=";"></span><span data-code-text=" "></span><span class="pl-k" data-code-text="then"></span></div></div><div data-key="175" class="react-code-text react-code-line-contents virtual" style="transform: translateY(3500px); min-height: auto;"><div id="LC176" class="react-file-line html-div" data-testid="code-cell" data-line-number="176" style="position: relative;"><span data-code-text="    "></span><span class="pl-k" data-code-text="if"></span><span data-code-text=" [[ "></span><span class="pl-k" data-code-text="-f"></span><span data-code-text=" "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span class="pl-smi" data-code-text="${XPUI_BAK}"></span><span class="pl-pds" data-code-text="&quot;"></span></span><span data-code-text=" ]]"></span><span class="pl-k" data-code-text=";"></span><span data-code-text=" "></span><span class="pl-k" data-code-text="then"></span></div></div><div data-key="176" class="react-code-text react-code-line-contents virtual" style="transform: translateY(3520px); min-height: auto;"><div id="LC177" class="react-file-line html-div" data-testid="code-cell" data-line-number="177" style="position: relative;"><span data-code-text="      "></span><span class="pl-c1" data-code-text="echo"></span><span data-code-text=" "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span data-code-text="SpotX backup found, SpotX has already been used on this install."></span><span class="pl-pds" data-code-text="&quot;"></span></span></div></div><div data-key="177" class="react-code-text react-code-line-contents virtual" style="transform: translateY(3540px); min-height: auto;"><div id="LC178" class="react-file-line html-div" data-testid="code-cell" data-line-number="178" style="position: relative;"><span data-code-text="      "></span><span class="pl-c1" data-code-text="echo"></span><span data-code-text=" -e "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span data-code-text="Re-run SpotX using the '-f' flag to force xpui patching.\n"></span><span class="pl-pds" data-code-text="&quot;"></span></span></div></div><div data-key="178" class="react-code-text react-code-line-contents virtual" style="transform: translateY(3560px); min-height: auto;"><div id="LC179" class="react-file-line html-div" data-testid="code-cell" data-line-number="179" style="position: relative;"><span data-code-text="      "></span><span class="pl-c1" data-code-text="echo"></span><span data-code-text=" "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span data-code-text="Skipping xpui patches and continuing SpotX..."></span><span class="pl-pds" data-code-text="&quot;"></span></span></div></div><div data-key="179" class="react-code-text react-code-line-contents virtual" style="transform: translateY(3580px); min-height: auto;"><div id="LC180" class="react-file-line html-div" data-testid="code-cell" data-line-number="180" style="position: relative;"><span data-code-text="      XPUI_SKIP="></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span data-code-text="true"></span><span class="pl-pds" data-code-text="&quot;"></span></span></div></div><div data-key="180" class="react-code-text react-code-line-contents virtual" style="transform: translateY(3600px); min-height: auto;"><div id="LC181" class="react-file-line html-div" data-testid="code-cell" data-line-number="181" style="position: relative;"><span data-code-text="    "></span><span class="pl-k" data-code-text="else"></span></div></div><div data-key="181" class="react-code-text react-code-line-contents virtual" style="transform: translateY(3620px); min-height: auto;"><div id="LC182" class="react-file-line html-div" data-testid="code-cell" data-line-number="182" style="position: relative;"><span data-code-text="      "></span><span class="pl-c1" data-code-text="echo"></span><span data-code-text=" "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span data-code-text="Creating xpui backup..."></span><span class="pl-pds" data-code-text="&quot;"></span></span></div></div><div data-key="182" class="react-code-text react-code-line-contents virtual" style="transform: translateY(3640px); min-height: auto;"><div id="LC183" class="react-file-line html-div" data-testid="code-cell" data-line-number="183" style="position: relative;"><span data-code-text="      cp "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span class="pl-smi" data-code-text="${XPUI_SPA}"></span><span class="pl-pds" data-code-text="&quot;"></span></span><span data-code-text=" "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span class="pl-smi" data-code-text="${XPUI_BAK}"></span><span class="pl-pds" data-code-text="&quot;"></span></span></div></div><div data-key="183" class="react-code-text react-code-line-contents virtual" style="transform: translateY(3660px); min-height: auto;"><div id="LC184" class="react-file-line html-div" data-testid="code-cell" data-line-number="184" style="position: relative;"><span data-code-text="      XPUI_SKIP="></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span data-code-text="false"></span><span class="pl-pds" data-code-text="&quot;"></span></span><span class="pl-k" data-code-text=";"></span><span data-code-text=" "></span><span class="pl-k" data-code-text="fi"></span></div></div><div data-key="184" class="react-code-text react-code-line-contents virtual" style="transform: translateY(3680px); min-height: auto;"><div id="LC185" class="react-file-line html-div" data-testid="code-cell" data-line-number="185" style="position: relative;"><span data-code-text="  "></span><span class="pl-k" data-code-text="else"></span></div></div><div data-key="185" class="react-code-text react-code-line-contents virtual" style="transform: translateY(3700px); min-height: auto;"><div id="LC186" class="react-file-line html-div" data-testid="code-cell" data-line-number="186" style="position: relative;"><span data-code-text="    "></span><span class="pl-k" data-code-text="if"></span><span data-code-text=" [[ "></span><span class="pl-k" data-code-text="-f"></span><span data-code-text=" "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span class="pl-smi" data-code-text="${XPUI_BAK}"></span><span class="pl-pds" data-code-text="&quot;"></span></span><span data-code-text=" ]]"></span><span class="pl-k" data-code-text=";"></span><span data-code-text=" "></span><span class="pl-k" data-code-text="then"></span></div></div><div data-key="186" class="react-code-text react-code-line-contents virtual" style="transform: translateY(3720px); min-height: auto;"><div id="LC187" class="react-file-line html-div" data-testid="code-cell" data-line-number="187" style="position: relative;"><span data-code-text="      "></span><span class="pl-c1" data-code-text="echo"></span><span data-code-text=" "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span data-code-text="Backup xpui found, restoring original..."></span><span class="pl-pds" data-code-text="&quot;"></span></span></div></div><div data-key="187" class="react-code-text react-code-line-contents virtual" style="transform: translateY(3740px); min-height: auto;"><div id="LC188" class="react-file-line html-div" data-testid="code-cell" data-line-number="188" style="position: relative;"><span data-code-text="      rm "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span class="pl-smi" data-code-text="${XPUI_SPA}"></span><span class="pl-pds" data-code-text="&quot;"></span></span></div></div><div data-key="188" class="react-code-text react-code-line-contents virtual" style="transform: translateY(3760px); min-height: auto;"><div id="LC189" class="react-file-line html-div" data-testid="code-cell" data-line-number="189" style="position: relative;"><span data-code-text="      cp "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span class="pl-smi" data-code-text="${XPUI_BAK}"></span><span class="pl-pds" data-code-text="&quot;"></span></span><span data-code-text=" "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span class="pl-smi" data-code-text="${XPUI_SPA}"></span><span class="pl-pds" data-code-text="&quot;"></span></span></div></div><div data-key="189" class="react-code-text react-code-line-contents virtual" style="transform: translateY(3780px); min-height: auto;"><div id="LC190" class="react-file-line html-div" data-testid="code-cell" data-line-number="190" style="position: relative;"><span data-code-text="      XPUI_SKIP="></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span data-code-text="false"></span><span class="pl-pds" data-code-text="&quot;"></span></span></div></div><div data-key="190" class="react-code-text react-code-line-contents virtual" style="transform: translateY(3800px); min-height: auto;"><div id="LC191" class="react-file-line html-div" data-testid="code-cell" data-line-number="191" style="position: relative;"><span data-code-text="    "></span><span class="pl-k" data-code-text="else"></span></div></div><div data-key="191" class="react-code-text react-code-line-contents virtual" style="transform: translateY(3820px); min-height: auto;"><div id="LC192" class="react-file-line html-div" data-testid="code-cell" data-line-number="192" style="position: relative;"><span data-code-text="      "></span><span class="pl-c1" data-code-text="echo"></span><span data-code-text=" "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span data-code-text="Creating xpui backup..."></span><span class="pl-pds" data-code-text="&quot;"></span></span></div></div><div data-key="192" class="react-code-text react-code-line-contents virtual" style="transform: translateY(3840px); min-height: auto;"><div id="LC193" class="react-file-line html-div" data-testid="code-cell" data-line-number="193" style="position: relative;"><span data-code-text="      cp "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span class="pl-smi" data-code-text="${XPUI_SPA}"></span><span class="pl-pds" data-code-text="&quot;"></span></span><span data-code-text=" "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span class="pl-smi" data-code-text="${XPUI_BAK}"></span><span class="pl-pds" data-code-text="&quot;"></span></span></div></div><div data-key="193" class="react-code-text react-code-line-contents virtual" style="transform: translateY(3860px); min-height: auto;"><div id="LC194" class="react-file-line html-div" data-testid="code-cell" data-line-number="194" style="position: relative;"><span data-code-text="      XPUI_SKIP="></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span data-code-text="false"></span><span class="pl-pds" data-code-text="&quot;"></span></span><span class="pl-k" data-code-text=";"></span><span data-code-text=" "></span><span class="pl-k" data-code-text="fi"></span><span class="pl-k" data-code-text=";"></span><span data-code-text=" "></span><span class="pl-k" data-code-text="fi"></span><span class="pl-k" data-code-text=";"></span><span data-code-text=" "></span><span class="pl-k" data-code-text="fi"></span></div></div><div data-key="194" class="react-code-text react-code-line-contents virtual" style="transform: translateY(3880px); min-height: auto;"><div id="LC195" class="react-file-line html-div" data-testid="code-cell" data-line-number="195" style="position: relative;"><span data-code-text=""></span></div></div><div data-key="195" class="react-code-text react-code-line-contents virtual" style="transform: translateY(3900px); min-height: auto;"><div id="LC196" class="react-file-line html-div" data-testid="code-cell" data-line-number="196" style="position: relative;"><span class="pl-c"><span class="pl-c" data-code-text="#"></span><span data-code-text=" Extract xpui.spa"></span></span></div></div><div data-key="196" class="react-code-text react-code-line-contents virtual" style="transform: translateY(3920px); min-height: auto;"><div id="LC197" class="react-file-line html-div" data-testid="code-cell" data-line-number="197" style="position: relative;"><span class="pl-k" data-code-text="if"></span><span data-code-text=" [[ "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span class="pl-smi" data-code-text="${XPUI_SKIP}"></span><span class="pl-pds" data-code-text="&quot;"></span></span><span data-code-text=" "></span><span class="pl-k" data-code-text="=="></span><span data-code-text=" "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span data-code-text="false"></span><span class="pl-pds" data-code-text="&quot;"></span></span><span data-code-text=" ]]"></span><span class="pl-k" data-code-text=";"></span><span data-code-text=" "></span><span class="pl-k" data-code-text="then"></span></div></div><div data-key="197" class="react-code-text react-code-line-contents virtual" style="transform: translateY(3940px); min-height: auto;"><div id="LC198" class="react-file-line html-div" data-testid="code-cell" data-line-number="198" style="position: relative;"><span data-code-text="  "></span><span class="pl-c1" data-code-text="echo"></span><span data-code-text=" "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span data-code-text="Extracting xpui..."></span><span class="pl-pds" data-code-text="&quot;"></span></span></div></div><div data-key="198" class="react-code-text react-code-line-contents virtual" style="transform: translateY(3960px); min-height: auto;"><div id="LC199" class="react-file-line html-div" data-testid="code-cell" data-line-number="199" style="position: relative;"><span data-code-text="  unzip -qq "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span class="pl-smi" data-code-text="${XPUI_SPA}"></span><span class="pl-pds" data-code-text="&quot;"></span></span><span data-code-text=" -d "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span class="pl-smi" data-code-text="${XPUI_DIR}"></span><span class="pl-pds" data-code-text="&quot;"></span></span></div></div><div data-key="199" class="react-code-text react-code-line-contents virtual" style="transform: translateY(3980px); min-height: auto;"><div id="LC200" class="react-file-line html-div" data-testid="code-cell" data-line-number="200" style="position: relative;"><span data-code-text="  "></span><span class="pl-k" data-code-text="if"></span><span data-code-text=" grep -Fq "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span data-code-text="SpotX"></span><span class="pl-pds" data-code-text="&quot;"></span></span><span data-code-text=" "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span class="pl-smi" data-code-text="${XPUI_JS}"></span><span class="pl-pds" data-code-text="&quot;"></span></span><span class="pl-k" data-code-text=";"></span><span data-code-text=" "></span><span class="pl-k" data-code-text="then"></span></div></div><div data-key="200" class="react-code-text react-code-line-contents virtual" style="transform: translateY(4000px); min-height: auto;"><div id="LC201" class="react-file-line html-div" data-testid="code-cell" data-line-number="201" style="position: relative;"><span data-code-text="    "></span><span class="pl-c1" data-code-text="echo"></span><span data-code-text=" -e "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span data-code-text="\nWarning: Detected SpotX patches but no backup file!"></span><span class="pl-pds" data-code-text="&quot;"></span></span></div></div><div data-key="201" class="react-code-text react-code-line-contents virtual" style="transform: translateY(4020px); min-height: auto;"><div id="LC202" class="react-file-line html-div" data-testid="code-cell" data-line-number="202" style="position: relative;"><span data-code-text="    "></span><span class="pl-c1" data-code-text="echo"></span><span data-code-text=" -e "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span data-code-text="Further xpui patching not allowed until Spotify is reinstalled/upgraded.\n"></span><span class="pl-pds" data-code-text="&quot;"></span></span></div></div><div data-key="202" class="react-code-text react-code-line-contents virtual" style="transform: translateY(4040px); min-height: auto;"><div id="LC203" class="react-file-line html-div" data-testid="code-cell" data-line-number="203" style="position: relative;"><span data-code-text="    "></span><span class="pl-c1" data-code-text="echo"></span><span data-code-text=" "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span data-code-text="Skipping xpui patches and continuing SpotX..."></span><span class="pl-pds" data-code-text="&quot;"></span></span></div></div><div data-key="203" class="react-code-text react-code-line-contents virtual" style="transform: translateY(4060px); min-height: auto;"><div id="LC204" class="react-file-line html-div" data-testid="code-cell" data-line-number="204" style="position: relative;"><span data-code-text="    XPUI_SKIP="></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span data-code-text="true"></span><span class="pl-pds" data-code-text="&quot;"></span></span></div></div><div data-key="204" class="react-code-text react-code-line-contents virtual" style="transform: translateY(4080px); min-height: auto;"><div id="LC205" class="react-file-line html-div" data-testid="code-cell" data-line-number="205" style="position: relative;"><span data-code-text="    rm "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span class="pl-smi" data-code-text="${XPUI_BAK}"></span><span class="pl-pds" data-code-text="&quot;"></span></span><span data-code-text=" "></span><span class="pl-k" data-code-text="2&gt;"></span><span data-code-text="/dev/null"></span></div></div><div data-key="205" class="react-code-text react-code-line-contents virtual" style="transform: translateY(4100px); min-height: auto;"><div id="LC206" class="react-file-line html-div" data-testid="code-cell" data-line-number="206" style="position: relative;"><span data-code-text="    rm -rf "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span class="pl-smi" data-code-text="${XPUI_DIR}"></span><span class="pl-pds" data-code-text="&quot;"></span></span><span data-code-text=" "></span><span class="pl-k" data-code-text="2&gt;"></span><span data-code-text="/dev/null"></span></div></div><div data-key="206" class="react-code-text react-code-line-contents virtual" style="transform: translateY(4120px); min-height: auto;"><div id="LC207" class="react-file-line html-div" data-testid="code-cell" data-line-number="207" style="position: relative;"><span data-code-text="  "></span><span class="pl-k" data-code-text="else"></span></div></div><div data-key="207" class="react-code-text react-code-line-contents virtual" style="transform: translateY(4140px); min-height: auto;"><div id="LC208" class="react-file-line html-div" data-testid="code-cell" data-line-number="208" style="position: relative;"><span data-code-text="    rm "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span class="pl-smi" data-code-text="${XPUI_SPA}"></span><span class="pl-pds" data-code-text="&quot;"></span></span><span class="pl-k" data-code-text=";"></span><span data-code-text=" "></span><span class="pl-k" data-code-text="fi"></span><span class="pl-k" data-code-text=";"></span><span data-code-text=" "></span><span class="pl-k" data-code-text="fi"></span></div></div><div data-key="208" class="react-code-text react-code-line-contents virtual" style="transform: translateY(4160px); min-height: auto;"><div id="LC209" class="react-file-line html-div" data-testid="code-cell" data-line-number="209" style="position: relative;"><span data-code-text=""></span></div></div><div data-key="209" class="react-code-text react-code-line-contents virtual" style="transform: translateY(4180px); min-height: auto;"><div id="LC210" class="react-file-line html-div" data-testid="code-cell" data-line-number="210" style="position: relative;"><span class="pl-c1" data-code-text="echo"></span><span data-code-text=" "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span data-code-text="Applying SpotX patches..."></span><span class="pl-pds" data-code-text="&quot;"></span></span></div></div><div data-key="210" class="react-code-text react-code-line-contents virtual" style="transform: translateY(4200px); min-height: auto;"><div id="LC211" class="react-file-line html-div" data-testid="code-cell" data-line-number="211" style="position: relative;"><span data-code-text=""></span></div></div><div data-key="211" class="react-code-text react-code-line-contents virtual" style="transform: translateY(4220px); min-height: auto;"><div id="LC212" class="react-file-line html-div" data-testid="code-cell" data-line-number="212" style="position: relative;"><span class="pl-k" data-code-text="if"></span><span data-code-text=" [[ "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span class="pl-smi" data-code-text="${XPUI_SKIP}"></span><span class="pl-pds" data-code-text="&quot;"></span></span><span data-code-text=" "></span><span class="pl-k" data-code-text="=="></span><span data-code-text=" "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span data-code-text="false"></span><span class="pl-pds" data-code-text="&quot;"></span></span><span data-code-text=" ]]"></span><span class="pl-k" data-code-text=";"></span><span data-code-text=" "></span><span class="pl-k" data-code-text="then"></span></div></div><div data-key="212" class="react-code-text react-code-line-contents virtual" style="transform: translateY(4240px); min-height: auto;"><div id="LC213" class="react-file-line html-div" data-testid="code-cell" data-line-number="213" style="position: relative;"><span data-code-text="  "></span><span class="pl-k" data-code-text="if"></span><span data-code-text=" [[ "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span class="pl-smi" data-code-text="${PREMIUM_FLAG}"></span><span class="pl-pds" data-code-text="&quot;"></span></span><span data-code-text=" "></span><span class="pl-k" data-code-text="=="></span><span data-code-text=" "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span data-code-text="false"></span><span class="pl-pds" data-code-text="&quot;"></span></span><span data-code-text=" ]]"></span><span class="pl-k" data-code-text=";"></span><span data-code-text=" "></span><span class="pl-k" data-code-text="then"></span></div></div><div data-key="213" class="react-code-text react-code-line-contents virtual" style="transform: translateY(4260px); min-height: auto;"><div id="LC214" class="react-file-line html-div" data-testid="code-cell" data-line-number="214" style="position: relative;"><span data-code-text="    "></span><span class="pl-c"><span class="pl-c" data-code-text="#"></span><span data-code-text=" Remove Empty ad block"></span></span></div></div><div data-key="214" class="react-code-text react-code-line-contents virtual" style="transform: translateY(4280px); min-height: auto;"><div id="LC215" class="react-file-line html-div" data-testid="code-cell" data-line-number="215" style="position: relative;"><span data-code-text="    "></span><span class="pl-c1" data-code-text="echo"></span><span data-code-text=" "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span data-code-text="Removing ad-related content..."></span><span class="pl-pds" data-code-text="&quot;"></span></span></div></div><div data-key="215" class="react-code-text react-code-line-contents virtual" style="transform: translateY(4300px); min-height: auto;"><div id="LC216" class="react-file-line html-div" data-testid="code-cell" data-line-number="216" style="position: relative;"><span data-code-text="    "></span><span class="pl-smi" data-code-text="$PERL"></span><span data-code-text=" "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span class="pl-smi" data-code-text="${AD_EMPTY_AD_BLOCK}"></span><span class="pl-pds" data-code-text="&quot;"></span></span><span data-code-text=" "></span><span class="pl-s"><span class="pl-pds" data-code-text="&quot;"></span><span class="pl-smi" data-code-text="${XPUI_JS}"></span><span class="pl-pds" data-code-text="&quot;"></span></span></div></div></div><button data-hotkey="Control+a" hidden=""></button><div aria-hidden="true" style="top: 0px; left: 80px;" data-testid="navigation-cursor" class="Box-sc-g0xbh4-0 code-navigation-cursor"> </div><button data-testid="NavigationCursorEnter" data-hotkey="Control+Enter" data-hotkey-scope="read-only-cursor-text-area" hidden=""></button><button data-testid="NavigationCursorSetHighlightedLine" data-hotkey="J" data-hotkey-scope="read-only-cursor-text-area" hidden=""></button><button data-testid="NavigationCursorPageDown" data-hotkey="PageDown" data-hotkey-scope="read-only-cursor-text-area" hidden=""></button><button data-testid="NavigationCursorPageUp" data-hotkey="PageUp" data-hotkey-scope="read-only-cursor-text-area" hidden=""></button><button data-testid="" data-hotkey="/" data-hotkey-scope="read-only-cursor-text-area" hidden=""></button></div></div><div class="Box-sc-g0xbh4-0 cceqnD"><div class="Box-sc-g0xbh4-0 izzOhr"></div></div></div></div><div id="highlighted-line-menu-container"></div></div></div></section></div><div class="Popover js-hovercard-content position-absolute" style="display: none; outline: none;" tabindex="0"><div class="Popover-message Popover-message--bottom-left Popover-message--large Box color-shadow-large" style="width: 360px;"></div></div></div></div>   </div></div></div><div class="Box-sc-g0xbh4-0"></div></main></div></div></div><div id="find-result-marks-container" class="Box-sc-g0xbh4-0 aZrVR"></div><button data-testid="" data-hotkey="Control+F6,Control+Shift+F6" data-hotkey-scope="read-only-cursor-text-area" hidden=""></button><button data-hotkey="Control+F6,Control+Shift+F6" hidden=""></button></div>    </div><script type="application/json" id="__PRIMER_DATA__">{"resolvedServerColorMode":"night"}</script></div>
</react-app>




  </div>

</turbo-frame>

    </main>
  </div>

  </div>

          <footer class="footer width-full container-xl p-responsive" role="contentinfo" hidden="">
  <h2 class="sr-only">Footer</h2>

  <div class="position-relative d-flex flex-items-center pb-2 f6 color-fg-muted color-border-muted flex-column-reverse flex-lg-row flex-wrap flex-lg-nowrap mt-0 pt-6">
    <div class="list-style-none d-flex flex-wrap col-0 col-lg-2 flex-justify-start flex-lg-justify-between mb-2 mb-lg-0">
      <div class="mt-2 mt-lg-0 d-flex flex-items-center">
        <a aria-label="Homepage" title="GitHub" class="footer-octicon mr-2" href="https://github.com/">
          <svg aria-hidden="true" height="24" viewBox="0 0 16 16" version="1.1" width="24" data-view-component="true" class="octicon octicon-mark-github">
    <path d="M8 0c4.42 0 8 3.58 8 8a8.013 8.013 0 0 1-5.45 7.59c-.4.08-.55-.17-.55-.38 0-.27.01-1.13.01-2.2 0-.75-.25-1.23-.54-1.48 1.78-.2 3.65-.88 3.65-3.95 0-.88-.31-1.59-.82-2.15.08-.2.36-1.02-.08-2.12 0 0-.67-.22-2.2.82-.64-.18-1.32-.27-2-.27-.68 0-1.36.09-2 .27-1.53-1.03-2.2-.82-2.2-.82-.44 1.1-.16 1.92-.08 2.12-.51.56-.82 1.28-.82 2.15 0 3.06 1.86 3.75 3.64 3.95-.23.2-.44.55-.51 1.07-.46.21-1.61.55-2.33-.66-.15-.24-.6-.83-1.23-.82-.67.01-.27.38.01.53.34.19.73.9.82 1.13.16.45.68 1.31 2.69.94 0 .67.01 1.3.01 1.49 0 .21-.15.45-.55.38A7.995 7.995 0 0 1 0 8c0-4.42 3.58-8 8-8Z"></path>
</svg>
</a>        <span>
        © 2023 GitHub, Inc.
        </span>
      </div>
    </div>

    <nav aria-label="Footer" class="col-12 col-lg-8">
      <h3 class="sr-only" id="sr-footer-heading">Footer navigation</h3>
      <ul class="list-style-none d-flex flex-wrap col-12 flex-justify-center flex-lg-justify-between mb-2 mb-lg-0" aria-labelledby="sr-footer-heading">
          <li class="mr-3 mr-lg-0"><a href="https://docs.github.com/site-policy/github-terms/github-terms-of-service" data-analytics-event="{&quot;category&quot;:&quot;Footer&quot;,&quot;action&quot;:&quot;go to terms&quot;,&quot;label&quot;:&quot;text:terms&quot;}">Terms</a></li>
          <li class="mr-3 mr-lg-0"><a href="https://docs.github.com/site-policy/privacy-policies/github-privacy-statement" data-analytics-event="{&quot;category&quot;:&quot;Footer&quot;,&quot;action&quot;:&quot;go to privacy&quot;,&quot;label&quot;:&quot;text:privacy&quot;}">Privacy</a></li>
          <li class="mr-3 mr-lg-0"><a data-analytics-event="{&quot;category&quot;:&quot;Footer&quot;,&quot;action&quot;:&quot;go to security&quot;,&quot;label&quot;:&quot;text:security&quot;}" href="https://github.com/security">Security</a></li>
          <li class="mr-3 mr-lg-0"><a href="https://www.githubstatus.com/" data-analytics-event="{&quot;category&quot;:&quot;Footer&quot;,&quot;action&quot;:&quot;go to status&quot;,&quot;label&quot;:&quot;text:status&quot;}">Status</a></li>
          <li class="mr-3 mr-lg-0"><a data-ga-click="Footer, go to help, text:Docs" href="https://docs.github.com/">Docs</a></li>
          <li class="mr-3 mr-lg-0"><a href="https://support.github.com/?tags=dotcom-footer" data-analytics-event="{&quot;category&quot;:&quot;Footer&quot;,&quot;action&quot;:&quot;go to contact&quot;,&quot;label&quot;:&quot;text:contact&quot;}">Contact GitHub</a></li>
          <li class="mr-3 mr-lg-0"><a href="https://github.com/pricing" data-analytics-event="{&quot;category&quot;:&quot;Footer&quot;,&quot;action&quot;:&quot;go to Pricing&quot;,&quot;label&quot;:&quot;text:Pricing&quot;}">Pricing</a></li>
        <li class="mr-3 mr-lg-0"><a href="https://docs.github.com/" data-analytics-event="{&quot;category&quot;:&quot;Footer&quot;,&quot;action&quot;:&quot;go to api&quot;,&quot;label&quot;:&quot;text:api&quot;}">API</a></li>
        <li class="mr-3 mr-lg-0"><a href="https://services.github.com/" data-analytics-event="{&quot;category&quot;:&quot;Footer&quot;,&quot;action&quot;:&quot;go to training&quot;,&quot;label&quot;:&quot;text:training&quot;}">Training</a></li>
          <li class="mr-3 mr-lg-0"><a href="https://github.blog/" data-analytics-event="{&quot;category&quot;:&quot;Footer&quot;,&quot;action&quot;:&quot;go to blog&quot;,&quot;label&quot;:&quot;text:blog&quot;}">Blog</a></li>
          <li><a data-ga-click="Footer, go to about, text:about" href="https://github.com/about">About</a></li>
      </ul>
    </nav>
  </div>

  <div class="d-flex flex-justify-center pb-6">
    <span class="f6 color-fg-muted"></span>
  </div>
</footer>




  <div id="ajax-error-message" class="ajax-error-message flash flash-error" hidden="">
    <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-alert">
    <path d="M6.457 1.047c.659-1.234 2.427-1.234 3.086 0l6.082 11.378A1.75 1.75 0 0 1 14.082 15H1.918a1.75 1.75 0 0 1-1.543-2.575Zm1.763.707a.25.25 0 0 0-.44 0L1.698 13.132a.25.25 0 0 0 .22.368h12.164a.25.25 0 0 0 .22-.368Zm.53 3.996v2.5a.75.75 0 0 1-1.5 0v-2.5a.75.75 0 0 1 1.5 0ZM9 11a1 1 0 1 1-2 0 1 1 0 0 1 2 0Z"></path>
</svg>
    <button type="button" class="flash-close js-ajax-error-dismiss" aria-label="Dismiss error">
      <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-x">
    <path d="M3.72 3.72a.75.75 0 0 1 1.06 0L8 6.94l3.22-3.22a.749.749 0 0 1 1.275.326.749.749 0 0 1-.215.734L9.06 8l3.22 3.22a.749.749 0 0 1-.326 1.275.749.749 0 0 1-.734-.215L8 9.06l-3.22 3.22a.751.751 0 0 1-1.042-.018.751.751 0 0 1-.018-1.042L6.94 8 3.72 4.78a.75.75 0 0 1 0-1.06Z"></path>
</svg>
    </button>
    You can’t perform that action at this time.
  </div>

  <div class="js-stale-session-flash flash flash-warn flash-banner" hidden="">
    <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-alert">
    <path d="M6.457 1.047c.659-1.234 2.427-1.234 3.086 0l6.082 11.378A1.75 1.75 0 0 1 14.082 15H1.918a1.75 1.75 0 0 1-1.543-2.575Zm1.763.707a.25.25 0 0 0-.44 0L1.698 13.132a.25.25 0 0 0 .22.368h12.164a.25.25 0 0 0 .22-.368Zm.53 3.996v2.5a.75.75 0 0 1-1.5 0v-2.5a.75.75 0 0 1 1.5 0ZM9 11a1 1 0 1 1-2 0 1 1 0 0 1 2 0Z"></path>
</svg>
    <span class="js-stale-session-flash-signed-in" hidden="">You signed in with another tab or window. <a href="">Reload</a> to refresh your session.</span>
    <span class="js-stale-session-flash-signed-out" hidden="">You signed out in another tab or window. <a href="">Reload</a> to refresh your session.</span>
  </div>
    <template id="site-details-dialog">
  <details class="details-reset details-overlay details-overlay-dark lh-default color-fg-default hx_rsm" open="">
    <summary role="button" aria-label="Close dialog"></summary>
    <details-dialog class="Box Box--overlay d-flex flex-column anim-fade-in fast hx_rsm-dialog hx_rsm-modal">
      <button class="Box-btn-octicon m-0 btn-octicon position-absolute right-0 top-0" type="button" aria-label="Close dialog" data-close-dialog="">
        <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-x">
    <path d="M3.72 3.72a.75.75 0 0 1 1.06 0L8 6.94l3.22-3.22a.749.749 0 0 1 1.275.326.749.749 0 0 1-.215.734L9.06 8l3.22 3.22a.749.749 0 0 1-.326 1.275.749.749 0 0 1-.734-.215L8 9.06l-3.22 3.22a.751.751 0 0 1-1.042-.018.751.751 0 0 1-.018-1.042L6.94 8 3.72 4.78a.75.75 0 0 1 0-1.06Z"></path>
</svg>
      </button>
      <div class="octocat-spinner my-6 js-details-dialog-spinner"></div>
    </details-dialog>
  </details>
</template>

    <div class="Popover js-hovercard-content position-absolute" style="display: none; outline: none;" tabindex="0">
  <div class="Popover-message Popover-message--bottom-left Popover-message--large Box color-shadow-large" style="width:360px;">
  </div>
</div>

    <template id="snippet-clipboard-copy-button">
  <div class="zeroclipboard-container position-absolute right-0 top-0">
    <clipboard-copy aria-label="Copy" class="ClipboardButton btn js-clipboard-copy m-2 p-0 tooltipped-no-delay" data-copy-feedback="Copied!" data-tooltip-direction="w">
      <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-copy js-clipboard-copy-icon m-2">
    <path d="M0 6.75C0 5.784.784 5 1.75 5h1.5a.75.75 0 0 1 0 1.5h-1.5a.25.25 0 0 0-.25.25v7.5c0 .138.112.25.25.25h7.5a.25.25 0 0 0 .25-.25v-1.5a.75.75 0 0 1 1.5 0v1.5A1.75 1.75 0 0 1 9.25 16h-7.5A1.75 1.75 0 0 1 0 14.25Z"></path><path d="M5 1.75C5 .784 5.784 0 6.75 0h7.5C15.216 0 16 .784 16 1.75v7.5A1.75 1.75 0 0 1 14.25 11h-7.5A1.75 1.75 0 0 1 5 9.25Zm1.75-.25a.25.25 0 0 0-.25.25v7.5c0 .138.112.25.25.25h7.5a.25.25 0 0 0 .25-.25v-7.5a.25.25 0 0 0-.25-.25Z"></path>
</svg>
      <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-check js-clipboard-check-icon color-fg-success d-none m-2">
    <path d="M13.78 4.22a.75.75 0 0 1 0 1.06l-7.25 7.25a.75.75 0 0 1-1.06 0L2.22 9.28a.751.751 0 0 1 .018-1.042.751.751 0 0 1 1.042-.018L6 10.94l6.72-6.72a.75.75 0 0 1 1.06 0Z"></path>
</svg>
    </clipboard-copy>
  </div>
</template>
<template id="snippet-clipboard-copy-button-unpositioned">
  <div class="zeroclipboard-container">
    <clipboard-copy aria-label="Copy" class="ClipboardButton btn btn-invisible js-clipboard-copy m-2 p-0 tooltipped-no-delay d-flex flex-justify-center flex-items-center" data-copy-feedback="Copied!" data-tooltip-direction="w">
      <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-copy js-clipboard-copy-icon">
    <path d="M0 6.75C0 5.784.784 5 1.75 5h1.5a.75.75 0 0 1 0 1.5h-1.5a.25.25 0 0 0-.25.25v7.5c0 .138.112.25.25.25h7.5a.25.25 0 0 0 .25-.25v-1.5a.75.75 0 0 1 1.5 0v1.5A1.75 1.75 0 0 1 9.25 16h-7.5A1.75 1.75 0 0 1 0 14.25Z"></path><path d="M5 1.75C5 .784 5.784 0 6.75 0h7.5C15.216 0 16 .784 16 1.75v7.5A1.75 1.75 0 0 1 14.25 11h-7.5A1.75 1.75 0 0 1 5 9.25Zm1.75-.25a.25.25 0 0 0-.25.25v7.5c0 .138.112.25.25.25h7.5a.25.25 0 0 0 .25-.25v-7.5a.25.25 0 0 0-.25-.25Z"></path>
</svg>
      <svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="octicon octicon-check js-clipboard-check-icon color-fg-success d-none">
    <path d="M13.78 4.22a.75.75 0 0 1 0 1.06l-7.25 7.25a.75.75 0 0 1-1.06 0L2.22 9.28a.751.751 0 0 1 .018-1.042.751.751 0 0 1 1.042-.018L6 10.94l6.72-6.72a.75.75 0 0 1 1.06 0Z"></path>
</svg>
    </clipboard-copy>
  </div>
</template>


    <style>
      .user-mention[href$="/anfreire"] {
        color: var(--color-user-mention-fg);
        background-color: var(--color-user-mention-bg);
        border-radius: 2px;
        margin-left: -2px;
        margin-right: -2px;
        padding: 0 2px;
      }
    </style>


    </div>

    <div id="js-global-screen-reader-notice" class="sr-only" aria-live="polite">SpotX-Linux/install.sh at main · SpotX-CLI/SpotX-Linux · GitHub&nbsp;</div>
  


</body></html>