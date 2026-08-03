import Foundation

enum LocalAPIHTMLStyle {
    static let fontStack = #"-apple-system, BlinkMacSystemFont, "Apple SD Gothic Neo", "Hiragino Sans", "Hiragino Kaku Gothic ProN", "Yu Gothic", "Meiryo", "PingFang SC", "Noto Sans CJK KR", "Segoe UI", sans-serif"#
    static let svgFontStack = "-apple-system,BlinkMacSystemFont,'Apple SD Gothic Neo','Hiragino Sans','Hiragino Kaku Gothic ProN','Yu Gothic',Meiryo,'PingFang SC','Noto Sans CJK KR','Segoe UI',sans-serif"

    static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

struct LocalAPIStaticAssetService {
    func response(for request: LocalHTTPRequest) -> LocalHTTPResponse {
        let lower = request.path.lowercased()
        switch lower {
        case "/loading.gif":
            let data = Data(
                base64Encoded: "R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw=="
            ) ?? Data()
            return LocalHTTPResponse.data(
                data,
                contentType: "image/gif",
                headers: ["Cache-Control": "public, max-age=86400"]
            )
        case "/favicon.ico":
            return iconAsset(
                name: "hitomi-native",
                color: request.query["color"]
            )
        case "/materialize.css":
            return LocalHTTPResponse.text(
                materializeCSS(),
                contentType: "text/css; charset=utf-8"
            )
        case "/hitomi.css":
            return LocalHTTPResponse.text(
                hitomiCSS(),
                contentType: "text/css; charset=utf-8"
            )
        case "/materialize.js":
            return LocalHTTPResponse.text(
                materializeJSStub(),
                contentType: "application/javascript; charset=utf-8"
            )
        case "/jquery.js":
            return LocalHTTPResponse.text(
                jqueryStub(),
                contentType: "application/javascript; charset=utf-8"
            )
        case "/lazysizes.js":
            return LocalHTTPResponse.text(
                lazySizesStub(),
                contentType: "application/javascript; charset=utf-8"
            )
        default:
            guard lower.hasPrefix("/icon/") else {
                return LocalHTTPResponse.jsonObject(
                    ["error": "Not found"],
                    status: 404
                )
            }
            let rawName = String(
                request.path.dropFirst("/icon/".count)
            )
            return iconAsset(name: rawName, color: request.query["color"])
        }
    }

    private func iconAsset(
        name rawName: String,
        color rawColor: String?
    ) -> LocalHTTPResponse {
        let name = rawName
            .split(separator: "/", omittingEmptySubsequences: true)
            .joined(separator: "-")
            .replacingOccurrences(
                of: "[^A-Za-z0-9_-]",
                with: "",
                options: .regularExpression
            )
        let iconName = name.isEmpty ? "item" : name
        let color = iconColor(rawColor)
        let label = iconLabel(iconName)
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64" role="img" aria-label="\(LocalAPIHTMLStyle.escape(iconName))">
          <rect width="64" height="64" rx="14" fill="\(color)"/>
          <circle cx="32" cy="32" r="20" fill="rgba(255,255,255,.16)"/>
          <text x="32" y="39" text-anchor="middle" font-family="\(LocalAPIHTMLStyle.svgFontStack)" font-size="18" font-weight="700" fill="#fff">\(LocalAPIHTMLStyle.escape(label))</text>
        </svg>
        """
        return LocalHTTPResponse.data(
            Data(svg.utf8),
            contentType: "image/svg+xml; charset=utf-8",
            headers: ["Cache-Control": "public, max-age=86400"]
        )
    }

    private func materializeCSS() -> String {
        """
        .waves-effect{position:relative;overflow:hidden}
        .btn,.btn-flat{display:inline-flex;align-items:center;justify-content:center;border:0;border-radius:4px;min-height:32px;padding:0 12px;cursor:pointer;text-decoration:none}
        .btn{background:#1a73e8;color:#fff}
        .btn-flat{background:transparent;color:#202124}
        .round{border-radius:999px}
        """
    }

    private func materializeJSStub() -> String {
        """
        (function(){
          var M = window.M = window.M || {};
          function toArray(value){if(!value)return[];if(typeof value==='string')return Array.prototype.slice.call(document.querySelectorAll(value));if(value.nodeType||value===window)return[value];if(typeof value.length==='number')return Array.prototype.slice.call(value).filter(Boolean);return[value];}
          function component(name){function C(el,options){this.el=el;this.options=options||{};if(el)el['M_'+name]=this;}C.init=function(els,options){var nodes=toArray(els);var instances=nodes.map(function(el){return el['M_'+name]||new C(el,options);});return nodes.length===1?instances[0]:instances;};C.getInstance=function(el){return el&&el['M_'+name]||null;};return C;}
          ['Dropdown','Modal','Sidenav','Tooltip','Collapsible','FormSelect','Tabs','Materialbox','Carousel','Datepicker','Timepicker'].forEach(function(name){M[name]=M[name]||component(name);});
          M.AutoInit = M.AutoInit || function(root){root=root||document;['Dropdown','Modal','Sidenav','Tooltip','Collapsible','FormSelect','Tabs','Materialbox','Carousel'].forEach(function(name){var selector='.'+name.replace(/[A-Z]/g,function(c,i){return(i?'-':'')+c.toLowerCase();});if(M[name]&&M[name].init)M[name].init(root.querySelectorAll(selector));});};
          M.updateTextFields = M.updateTextFields || function(){document.querySelectorAll('input, textarea').forEach(function(el){if(el.value)el.classList.add('valid');});};
          M.toast = M.toast || function(options){options=typeof options==='string'?{html:options}:(options||{});var container=document.querySelector('#toast-container');if(!container){container=document.createElement('div');container.id='toast-container';container.style.cssText='position:fixed;left:50%;bottom:24px;transform:translateX(-50%);z-index:9999;display:flex;flex-direction:column;gap:8px;align-items:center;';document.body.appendChild(container);}var toast=document.createElement('div');toast.className='toast';toast.innerHTML=options.html||options.text||'';toast.style.cssText='background:rgba(32,33,36,.92);color:white;padding:10px 14px;border-radius:4px;box-shadow:0 2px 8px rgba(0,0,0,.24);font:13px sans-serif;';container.appendChild(toast);var length=Number(options.displayLength||options.duration||3000);setTimeout(function(){toast.remove();},Math.max(500,length));return {el:toast,dismiss:function(){toast.remove();}};};
          M.Waves = M.Waves || {displayEffect:function(){}};
          if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',function(){M.AutoInit(document);});else M.AutoInit(document);
        }());
        """
    }

    private func hitomiCSS() -> String {
        """
        :root{--width-item-icon:20px;--height-item-icon:20px}
        body{font-family:\(LocalAPIHTMLStyle.fontStack)}
        .item-icon{width:var(--width-item-icon);height:var(--height-item-icon);object-fit:contain}
        .thumb,.thumb-bg{object-fit:cover}
        .pin{width:14px;height:14px}
        """
    }

    private func jqueryStub() -> String {
        """
        (function(){
          function toArray(value, context){
            if(!value) return [];
            if(value instanceof J) return value.nodes.slice();
            if(typeof value==='string') return Array.prototype.slice.call((context||document).querySelectorAll(value));
            if(value===window || value.nodeType) return [value];
            if(typeof value.length==='number') return Array.prototype.slice.call(value).filter(Boolean);
            return [value];
          }
          function J(nodes){this.nodes=toArray(nodes);}
          J.prototype.each=function(handler){this.nodes.forEach(function(n,i){handler.call(n,i,n);});return this;};
          J.prototype.find=function(selector){var found=[];this.nodes.forEach(function(n){if(n&&n.querySelectorAll)found=found.concat(toArray(selector,n));});return new J(found);};
          J.prototype.on=function(type,handler){this.nodes.forEach(function(n){n.addEventListener(type,handler);});return this;};
          ['mousedown','mouseover','mouseup','keyup','keydown','change','submit'].forEach(function(type){J.prototype[type]=function(handler){return this.on(type,handler);};});
          J.prototype.click=function(handler){return handler?this.on('click',handler):(this.nodes[0]&&this.nodes[0].click(),this);};
          J.prototype.html=function(value){if(value===undefined)return this.nodes[0]?this.nodes[0].innerHTML:'';this.nodes.forEach(function(n){n.innerHTML=value;});return this;};
          J.prototype.val=function(value){if(value===undefined)return this.nodes[0]?this.nodes[0].value:'';this.nodes.forEach(function(n){n.value=value;});return this;};
          J.prototype.attr=function(name,value){if(value===undefined)return this.nodes[0]?this.nodes[0].getAttribute(name):null;this.nodes.forEach(function(n){n.setAttribute(name,value);});return this;};
          J.prototype.hasClass=function(name){return !!(this.nodes[0]&&this.nodes[0].classList&&this.nodes[0].classList.contains(name));};
          J.prototype.addClass=function(name){this.nodes.forEach(function(n){if(n.classList)n.classList.add(name);});return this;};
          J.prototype.removeClass=function(name){this.nodes.forEach(function(n){if(n.classList)n.classList.remove(name);});return this;};
          J.prototype.toggleClass=function(name,state){this.nodes.forEach(function(n){if(!n.classList)return;if(state===undefined)n.classList.toggle(name);else n.classList.toggle(name,!!state);});return this;};
          J.prototype.show=function(){this.nodes.forEach(function(n){if(!n.style)return;n.style.display=n.classList&&n.classList.contains('tools')?'flex':'';if(getComputedStyle(n).display==='none')n.style.display='block';});return this;};
          J.prototype.hide=function(){this.nodes.forEach(function(n){if(n.style)n.style.display='none';});return this;};
          window.$=window.jQuery=window.$||function(selector,context){return new J(toArray(selector,context));};
          window.$.find=function(selector,context){return toArray(selector,context);};
          window.$.ajax=function(options){return fetch(options.url,{method:options.type||options.method||'GET',body:options.data}).then(function(r){return r.text().then(function(t){if(options.success)options.success(t,'success',r);return t;});});};
        }());
        """
    }

    private func lazySizesStub() -> String {
        """
        document.addEventListener('DOMContentLoaded',function(){
          document.querySelectorAll('img[data-src]').forEach(function(img){ if(!img.getAttribute('src') || img.classList.contains('lazyload')) img.setAttribute('src', img.getAttribute('data-src')); });
        });
        """
    }

    private func iconColor(_ raw: String?) -> String {
        let value = (raw ?? "1a73e8")
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .filter { $0.isHexDigit }
        guard [3, 4, 6, 8].contains(value.count) else {
            return "#1a73e8"
        }
        return "#\(value)"
    }

    private func iconLabel(_ name: String) -> String {
        let lower = name.lowercased()
        let labels: [String: String] = [
            "home": "H",
            "renew": "R",
            "delete": "D",
            "close": "X",
            "down": "DL",
            "folder_open": "F",
            "folder-open": "F",
            "pin": "P",
            "lock": "L",
            "music": "M",
            "live": "LV"
        ]
        if let label = labels[lower] {
            return label
        }
        let cleaned = lower.replacingOccurrences(of: "fav-", with: "")
        let initials = cleaned
            .split(separator: "-", omittingEmptySubsequences: true)
            .prefix(2)
            .compactMap(\.first)
            .map { String($0).uppercased() }
            .joined()
        return initials.isEmpty ? "HN" : initials
    }
}
