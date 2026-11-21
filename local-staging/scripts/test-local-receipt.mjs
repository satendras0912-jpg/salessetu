import { randomBytes } from "node:crypto";
const PORT = "55321";
export function assertLocalEndpoint(value) {
  const url = new URL(value);
  if (url.protocol !== "http:" || !["localhost","127.0.0.1"].includes(url.hostname) ||
      url.port !== PORT || url.username || url.password ||
      !["","/"].includes(url.pathname) || url.search || url.hash) {
    throw new Error("REFUSED: only http://127.0.0.1:55321 is allowed");
  }
  return url;
}
export async function runSmoke({ endpoint, serviceKey }) {
  const root = assertLocalEndpoint(endpoint);
  if (!serviceKey) throw new Error("Local service key required");
  const path = new URL("/rest/v1/rpc/local_ingest_test_receipt", root);
  const key = randomBytes(12).toString("hex").toUpperCase();
  const payload = { route_key:"kavyarpit-local-test",idempotency_key:"QA-"+key,synthetic_reference:"QA-"+key };
  const send = async (body) => {
    const resp = await fetch(path,{method:"POST",redirect:"error",headers:{"Content-Type":"application/json",apikey:serviceKey,Authorization:"Bearer "+serviceKey},body:JSON.stringify({p_payload:body}),signal:AbortSignal.timeout(10000)});
    const data = await resp.json().catch(()=>null);
    return {status:resp.status,data};
  };
  const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  const first=await send(payload);
  if(first.status!==200 || first.data?.status!=="processed" || first.data?.duplicate!==false ||
      !UUID.test(first.data?.intake_id??"") || !UUID.test(first.data?.lead_id??"")) throw new Error("Initial receipt failed");
  const second=await send(payload);
  if(second.status!==200 || second.data?.duplicate!==true ||
      second.data?.lead_id!==first.data.lead_id || second.data?.intake_id!==first.data.intake_id) throw new Error("Duplicate handling failed");
  const rejected=await send({...payload,route_key:"salessetu-web-demo"});
  if(rejected.status>=200 && rejected.status<300) throw new Error("Wrong route accepted");
  console.log(JSON.stringify({status:"PASS",mode:"LOCAL_CONTRACT_ONLY",checks:3,productionNetworkCalls:0},null,2));
}
if(process.argv[1]?.endsWith("test-local-receipt.mjs")) {
  runSmoke({endpoint:process.env.LOCAL_SUPABASE_URL??"http://127.0.0.1:55321",serviceKey:process.env.LOCAL_SUPABASE_SERVICE_ROLE_KEY}).catch(err=>{console.error(err.message);process.exitCode=1;});
}
