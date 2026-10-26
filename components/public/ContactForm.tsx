'use client';
import emailjs from '@emailjs/browser';
import { useRef,useState } from 'react';

export function ContactForm(){
 const form=useRef<HTMLFormElement>(null); const [status,setStatus]=useState<'idle'|'sending'|'sent'|'error'>('idle'); const [message,setMessage]=useState('');
 async function submit(e:React.FormEvent<HTMLFormElement>){e.preventDefault();setMessage('');
   const service=process.env.NEXT_PUBLIC_EMAILJS_SERVICE_ID; const template=process.env.NEXT_PUBLIC_EMAILJS_TEMPLATE_ID; const key=process.env.NEXT_PUBLIC_EMAILJS_PUBLIC_KEY;
   if(!service||!template||!key){setStatus('error');setMessage('EmailJS is not configured yet. Add the three EmailJS values to .env.local.');return}
   if(!form.current)return; setStatus('sending');
   try{await emailjs.sendForm(service,template,form.current,{publicKey:key,limitRate:{throttle:10000}});setStatus('sent');setMessage('Your message was sent successfully. We’ll get back to you soon.');form.current.reset()}
   catch{setStatus('error');setMessage('We could not send your message. Please try again in a moment.')}
 }
 return <form ref={form} className="contact-form" onSubmit={submit}>
   <div className="contact-fields"><label>Full name<input name="from_name" required minLength={2} placeholder="Your name"/></label><label>Email<input type="email" name="reply_to" required placeholder="you@example.com"/></label></div>
   <div className="contact-fields"><label>Organization<input name="organization" placeholder="University / hospital (optional)"/></label><label>Topic<select name="topic" defaultValue="Platform demo"><option>Platform demo</option><option>University partnership</option><option>Technical support</option><option>Clinical content</option><option>Other</option></select></label></div>
   <label>Message<textarea name="message" required minLength={10} placeholder="Tell us how we can help…"/></label>
   <input type="hidden" name="product" value="CareSim"/>
   {message&&<div className={`contact-message ${status}`}>{status==='sent'?<i className="fa-solid fa-circle-check"/>:<i className="fa-solid fa-circle-exclamation"/>}{message}</div>}
   <button className="btn primary contact-submit" disabled={status==='sending'}>{status==='sending'?<><i className="fa-solid fa-spinner fa-spin"/> Sending…</>:<>Send message <i className="fa-solid fa-paper-plane"/></>}</button>
 </form>
}
