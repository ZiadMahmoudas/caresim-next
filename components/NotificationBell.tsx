'use client';
import Link from 'next/link';
import { useEffect,useRef,useState } from 'react';
import { createClient } from '@/lib/supabase/client';

type Notice={id:string;title:string;body:string;href:string|null;kind:string;is_read:boolean;created_at:string};
export function NotificationBell(){
 const [items,setItems]=useState<Notice[]>([]); const [open,setOpen]=useState(false); const wrap=useRef<HTMLDivElement>(null);
 const unread=items.filter(x=>!x.is_read).length;
 async function load(){const s=createClient();const {data}=await s.from('notifications').select('id,title,body,href,kind,is_read,created_at').order('created_at',{ascending:false}).limit(8);setItems((data||[]) as Notice[])}
 useEffect(()=>{void load();const close=(e:MouseEvent)=>{if(wrap.current&&!wrap.current.contains(e.target as Node))setOpen(false)};document.addEventListener('mousedown',close);return()=>document.removeEventListener('mousedown',close)},[]);
 async function mark(id:string){const s=createClient();await s.from('notifications').update({is_read:true,read_at:new Date().toISOString()}).eq('id',id);setItems(v=>v.map(x=>x.id===id?{...x,is_read:true}:x))}
 async function markAll(){const s=createClient();await s.from('notifications').update({is_read:true,read_at:new Date().toISOString()}).eq('is_read',false);setItems(v=>v.map(x=>({...x,is_read:true})))}
 return <div className="notification-wrap" ref={wrap}><button className={`icon-button ${open?'active':''}`} aria-label="Notifications" onClick={()=>setOpen(v=>!v)}><i className="fa-regular fa-bell"/>{unread>0&&<span className="notification-count">{unread>9?'9+':unread}</span>}</button>{open&&<div className="notification-menu"><div className="notification-head"><div><span>Notifications</span><b>{unread?`${unread} unread`:'You’re all caught up'}</b></div>{unread>0&&<button onClick={markAll}>Mark all read</button>}</div><div className="notification-list">{items.length?items.map(n=>{const content=<><span className={`notice-icon ${n.kind}`}><i className={`fa-solid ${n.kind==='success'?'fa-circle-check':n.kind==='assignment'?'fa-list-check':n.kind==='achievement'?'fa-trophy':'fa-bell'}`}/></span><div><b>{n.title}</b><p>{n.body}</p><small>{new Date(n.created_at).toLocaleString(undefined,{month:'short',day:'numeric',hour:'numeric',minute:'2-digit'})}</small></div>{!n.is_read&&<i className="unread-dot"/>}</>;return n.href?<Link href={n.href} onClick={()=>{void mark(n.id);setOpen(false)}} className={`notification-item ${n.is_read?'':'unread'}`} key={n.id}>{content}</Link>:<button onClick={()=>mark(n.id)} className={`notification-item ${n.is_read?'':'unread'}`} key={n.id}>{content}</button>}) : <div className="notification-empty"><i className="fa-regular fa-bell-slash"/><b>No notifications yet</b><span>Your assignments, results and platform updates will appear here.</span></div>}</div></div>}</div>
}
