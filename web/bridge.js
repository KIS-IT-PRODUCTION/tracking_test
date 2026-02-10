window.flutterBridge = {
    elements: {},
    isTrackerLoaded: false,
    virtualScrollY: 0, 

    initTracker: function() {
        if (this.isTrackerLoaded) return;
        
        console.log("[Bridge] Initializing Tracker...");
        localStorage.removeItem('tracker_data_pending');

        // Патч для скролу
        try {
            const getScroll = () => this.virtualScrollY;
            Object.defineProperty(window, 'scrollY', { get: getScroll, configurable: true });
            Object.defineProperty(window, 'pageYOffset', { get: getScroll, configurable: true });
        } catch (e) {}

        this._ensureHiddenInput('ts1-client-id', '123');

        // === ВИПРАВЛЕННЯ ШЛЯХУ ===
        // Ми беремо base href прямо з HTML, який ми виправили вище
        const baseHref = document.querySelector('base') ? document.querySelector('base').href : '/tracking_test/';
        const scriptUrl = baseHref + 'tracker.js';

        console.log(`[Bridge] Loading tracker from: ${scriptUrl}`);

        const script = document.createElement('script');
        script.src = scriptUrl; 
        script.async = true;
        
        // Обробка помилок завантаження скрипта
        script.onerror = () => console.error("[Bridge] Failed to load tracker.js! Check if file exists in web folder.");
        script.onload = () => console.log("[Bridge] Tracker loaded successfully.");
        
        document.head.appendChild(script);
        
        this.isTrackerLoaded = true;
    },

    handleNavigation: function(prevPageName, newPageName) {
        // Захист від null/undefined
        prevPageName = prevPageName || 'null';
        newPageName = newPageName || '/';

        console.log(`[Bridge] Navigation: ${prevPageName} -> ${newPageName}`);

        if (prevPageName !== 'null') {
            this._simulateVisibilityChange('hidden');
            this._commitAndSend(prevPageName);
        }

        this.triggerUrlChange(newPageName);
        
        if (prevPageName !== 'null') {
            setTimeout(() => {
                this._simulateVisibilityChange('visible');
            }, 50);
        }
    },

    _simulateVisibilityChange: function(state) {
        // Безпечна зміна visibility
        try {
            Object.defineProperty(document, 'visibilityState', { value: state, writable: true });
            Object.defineProperty(document, 'hidden', { value: state === 'hidden', writable: true });
            document.dispatchEvent(new Event('visibilitychange'));
        } catch (e) {
            console.warn("[Bridge] Could not mock visibility:", e);
        }
    },

    _commitAndSend: function(pageName) {
        const data = this._mockCollectData(); 
        if (data) {
            console.log(`%c[Network] Sending data for ${pageName}`, "color: green");
        }
    },

    _mockCollectData: function() {
        const activeIds = Object.keys(this.elements);
        return activeIds.length > 0 ? { event: "page_data", inputs: activeIds } : null;
    },

    triggerScroll: function(pixels) {
        this.virtualScrollY = pixels;
        // Авто-розширення сторінки, щоб скрол працював коректно
        if (document.body.scrollHeight < pixels + window.innerHeight) {
            document.body.style.minHeight = (pixels + window.innerHeight + 100) + 'px';
        }
        window.dispatchEvent(new Event('scroll'));
    },

    triggerUrlChange: function(newUrl) {
        this.virtualScrollY = 0;
        // Просто повідомляємо аналітику, не чіпаємо URL браузера
        window.dispatchEvent(new Event('popstate'));
        window.dispatchEvent(new Event('locationchange')); 
    },

    triggerClick: function(id, x, y) {
        const el = this._getOrCreateElement(id, 'div');
        el.style.left = x + 'px'; el.style.top = y + 'px';
        const opts = { bubbles: true, cancelable: true, view: window, clientX: x, clientY: y };
        el.dispatchEvent(new MouseEvent('click', opts));
    },

    setFocus: function(id, hasFocus) {
        const el = this._getOrCreateElement(id, 'input');
        if (hasFocus) {
            el.focus();
            el.dispatchEvent(new Event('focus', { bubbles: true }));
        } else {
            el.blur();
            el.dispatchEvent(new Event('blur', { bubbles: true }));
        }
    },

    updateInput: function(id, text, isBackspace) {
         const el = this._getOrCreateElement(id, 'input');
         el.value = text;
         el.dispatchEvent(new InputEvent('input', { bubbles: true }));
    },

    _getOrCreateElement: function(id, type) {
        let el = document.getElementById(id);
        // Якщо тип елемента змінився (div -> input), перестворюємо
        if (el && el.tagName.toLowerCase() !== type) { el.remove(); el = null; }
        
        if (!el) {
            el = document.createElement(type);
            el.id = id;
            el.setAttribute('data-ts1-id', id); 
            // Робимо елемент прозорим, але фізично присутнім
            el.style.position = 'fixed';
            el.style.opacity = '0.01'; 
            el.style.pointerEvents = 'none'; // Щоб не перекривав Flutter
            el.style.zIndex = '-1'; 
            document.body.appendChild(el);
            this.elements[id] = el;
        }
        return el;
    },
    
    registerElement: function(id) {
        this._getOrCreateElement(id, 'div');
    },

    _ensureHiddenInput: function(id, value) {
        if (!document.getElementById(id)) {
            const i = document.createElement('input');
            i.id = id; i.type = 'hidden'; i.value = value;
            document.body.appendChild(i);
        }
    }
};