#include "Vtb_sva_top.h"
#include "verilated.h"
#include "verilated_cov.h"
#include <memory>

int main(int argc, char** argv) {
    auto context = std::make_unique<VerilatedContext>();
    context->commandArgs(argc, argv);
    auto model = std::make_unique<Vtb_sva_top>(context.get());
    while (!context->gotFinish()) {
        model->eval();
        if (!model->eventsPending()) break;
        context->time(model->nextTimeSlot());
    }
    model->final();
    context->coveragep()->write();
    return context->gotFinish() ? 0 : 1;
}
