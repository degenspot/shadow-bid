import { BarretenbergBackend } from '@noir-lang/backend_barretenberg';
import { Noir } from '@noir-lang/noir_js';
import circuit from '../../public/circuits/shadow_bid_circuits.json';

export class ZKProver {
    private backend: BarretenbergBackend;
    private noir: Noir;

    constructor() {
        // Initialize backend and noir with the circuit artifact
        // We cast to any because the JSON import type might not match exact NoirCompiledCircuit interface automatically
        this.backend = new BarretenbergBackend(circuit as any);
        this.noir = new Noir(circuit as any);
    }

    async generateProof(inputs: {
        bid_amount: string,
        min_price: string,
        max_price: string,
        salt: string
    }) {
        console.log("Generating proof with inputs:", inputs);

        // 1. Execute circuit to generate witness
        const { witness } = await this.noir.execute(inputs);

        // 2. Generate proof
        const proof = await this.backend.generateProof(witness);

        console.log("Proof generated length:", proof.proof.length);
        return proof.proof;
    }

    async verifyProof(proof: Uint8Array) {
        const isValid = await this.backend.verifyProof({ proof, publicInputs: [] }); // circuit has public inputs? 
        // Wait, our circuit has public inputs? 
        // main(bid_amount, min_price, max_price, salt) -> pub [hash]
        // The hash is public? No, in main.nr: 
        // fn main(bid: Field, min: pub Field, max: pub Field, salt: Field) -> pub Field
        // So min, max, and return (commitment) are public.
        // verifyProof inside JS usually checks it against the witness/inputs we just generated?
        // backend.verifyProof takes { proof, publicInputs }.
        return isValid;
    }
}
