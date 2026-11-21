import test from "node:test";
import assert from "node:assert/strict";
import { assertLocalEndpoint } from "./test-local-receipt.mjs";
test("accepts only local HTTP API port",()=>{
  assert.equal(assertLocalEndpoint("http://127.0.0.1:55321").port,"55321");
  assert.equal(assertLocalEndpoint("http://localhost:55321").port,"55321");
});
test("rejects remote endpoints and unsafe URLs",()=>{
  for(const value of ["https://example.supabase.co","http://192.168.1.9:55321","http://localhost:54321","https://localhost:55321","http://localhost:55321/other","http://u:p@localhost:55321","http://localhost:55321?foo=bar"]) assert.throws(()=>assertLocalEndpoint(value));
});
