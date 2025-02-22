// ==UserScript==
// @name         Redirect Twitter To Nitter
// @namespace    cmj 
// @version      1.0.0
// @description  Convert Twitter and X.com URLs to Nitter instance.
// @author       cmj
// @include      *
// @exclude      https://twitter.com/*
// @exclude      https://x.com/*
// @run-at       document-end
// @downloadURL  https://github.com/cmj/twitter-tools/Redirect_Twitter_To_Nitter.user.js
// ==/UserScript==

// nitter.net
// nitter.poast.org
// xcancel.com
// nitter.privacydev.net
// twitt.re
// nitter.aishiteiru.moe
// nitter.brainfuck.space

const NITTER_URL = 'nitter.net' // Nitter instance
const TWITTER_URL = 'twitter.com'
const XCOM_URL = 'x.com'

function redirectToNitter () {
    document.querySelectorAll('a[href*="'+ TWITTER_URL +'"]').forEach((element) => {
        element.href = element.href.replace(TWITTER_URL, NITTER_URL)
        element.textContent = element.textContent.replace(TWITTER_URL, NITTER_URL)
		})
		document.querySelectorAll('a[href*="'+ XCOM_URL +'"]').forEach((element) => {
        element.href = element.href.replace(XCOM_URL, NITTER_URL)
        element.textContent = element.textContent.replace(XCOM_URL, NITTER_URL)
    })
}

(new MutationObserver((mutations) => {
    let runCheck = false
    for (let mutation of mutations) {
        if (mutation.addedNodes.length || mutation.attributeName === 'href') {
            runCheck = true
            break
        }
    }
    if (runCheck) {
        redirectToNitter()
    }
})).observe(document.querySelector('body'), {attributeFilter: ['href'], childList: true, subtree: true})

redirectToNitter()
