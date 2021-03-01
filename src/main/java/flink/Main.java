package flink;

import java.util.Properties;

import org.apache.flink.streaming.api.datastream.DataStream;
import org.apache.flink.streaming.api.datastream.KeyedStream;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;
import org.apache.flink.streaming.api.windowing.assigners.TumblingProcessingTimeWindows;
import org.apache.flink.streaming.api.windowing.time.Time;
import org.apache.flink.streaming.connectors.kafka.FlinkKafkaConsumer;
import org.apache.flink.streaming.connectors.kafka.FlinkKafkaProducer;
import org.apache.flink.streaming.connectors.kafka.FlinkKafkaProducer.Semantic;

import flink.functions.*;
import flink.kafka_utility.*;
import flink.kafka_utility.KafkaRecord;

public class Main {

	public static void main(String[] args) throws Exception {

		StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();

		// parse user parameters
		// ParameterTool parameterTool = ParameterTool.fromArgs(args);

		Properties propertiesConsumer = new Properties();
		propertiesConsumer.setProperty("bootstrap.servers", "localhost:9092");
		propertiesConsumer.setProperty("group.id", "car");

		// Consumer
		FlinkKafkaConsumer<KafkaRecord> kafkaConsumer = new FlinkKafkaConsumer<KafkaRecord>("car-eu",
				new KafkaDeserialization(), propertiesConsumer);
		kafkaConsumer.setStartFromEarliest();

		// Producer
		FlinkKafkaProducer<KafkaRecord> kafkaProducerRegion = new FlinkKafkaProducer<KafkaRecord>("region-eu-analysis",
				new KafkaSerialization("region-eu-analysis"), propertiesConsumer, Semantic.EXACTLY_ONCE);
		FlinkKafkaProducer<KafkaRecord> kafkaProducerCar = new FlinkKafkaProducer<KafkaRecord>("car-eu-analysis",
				new KafkaSerialization("car-eu-analysis"), propertiesConsumer, Semantic.EXACTLY_ONCE);

		DataStream<KafkaRecord> regionStream = env.addSource(kafkaConsumer);

		KeyedStream<KafkaRecord, String> carStream = regionStream.filter(record -> record != null)
				.keyBy(record -> record.data.get("id").getAsString());



		// Detect cars with high speed
		carStream.window(TumblingProcessingTimeWindows.of(Time.seconds(3))).aggregate(new HighSpeedDetector())
				.filter(record -> record != null).addSink(kafkaProducerCar);


		// Counts all active cars
		regionStream.filter(record -> record != null).windowAll(TumblingProcessingTimeWindows.of(Time.seconds(5)))
				.aggregate(new ActiveCarsDetector()).addSink(kafkaProducerRegion);

		/*
		 * Count distinct car models
		 * 
		 * Aggregate all distinct IDs into one Tuple ("model", 1). Collect data and
		 * produce kafka record
		 */
		carStream.window(TumblingProcessingTimeWindows.of(Time.seconds(5))) // Every 5 seconds
				.aggregate(new ModelTypeDetector()).windowAll(TumblingProcessingTimeWindows.of(Time.seconds(1)))
				.process(new CollectDataModels()).addSink(kafkaProducerRegion);

		/*
		 * Count distinct fuel types
		 * 
		 * Aggregate all distinct IDs into one Tuple ("fuel", 1). Collect data and
		 * produce kafka record
		 */
		carStream.window(TumblingProcessingTimeWindows.of(Time.seconds(5))).aggregate(new FuelTypeDetector())
				.windowAll(TumblingProcessingTimeWindows.of(Time.seconds(1))).process(new CollectDataFuel())
				.addSink(kafkaProducerRegion);

		/*
		 * Position of all cars
		 * 
		 * Returns position of latest record in timeframe Collects positions and
		 * produces output record
		 */
		carStream.window(TumblingProcessingTimeWindows.of(Time.seconds(1))).process(new PosProcesser())
				.windowAll(TumblingProcessingTimeWindows.of(Time.seconds(1))).process(new CollectDataPos())
				.addSink(kafkaProducerRegion);

		System.out.println("Flink Job started.");

		env.execute();

	}
}