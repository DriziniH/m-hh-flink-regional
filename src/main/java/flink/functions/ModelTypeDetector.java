package flink.functions;

import java.util.ArrayList;
import org.apache.flink.api.common.functions.AggregateFunction;
import org.apache.flink.api.java.tuple.Tuple2;
import flink.kafka_utility.KafkaRecord;

public class ModelTypeDetector
        implements AggregateFunction<KafkaRecord, ArrayList<KafkaRecord>, Tuple2<String, Integer>> {

    private static final long serialVersionUID = 1L;

    @Override
    public ArrayList<KafkaRecord> createAccumulator() {
        return new ArrayList<KafkaRecord>();
    }

    @Override
    public ArrayList<KafkaRecord> add(KafkaRecord record, ArrayList<KafkaRecord> accumulator) {
        accumulator.add(record);
        return accumulator;
    }

    @Override
    public Tuple2<String, Integer> getResult(ArrayList<KafkaRecord> accumulator) {
        /**
         * Returns model type and 1 for distinct car -> is counted later on
         */

        String model = "";

        // Get car model from first car (all data records here are from the same car)
        for (KafkaRecord record : accumulator) {
            model = record.data.get("model").getAsString();
            break;
        }

        return new Tuple2<String, Integer>(model, 1);
    }

    @Override
    public ArrayList<KafkaRecord> merge(ArrayList<KafkaRecord> a, ArrayList<KafkaRecord> b) {
        a.addAll(b);
        return a;
    }

}
